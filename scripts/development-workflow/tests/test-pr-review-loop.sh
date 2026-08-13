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
_ADVISORY_TMP=""

# Single EXIT trap: normalise SIGPIPE exit code (141 -> 0) and clean up temp
# directories. A second trap would override this one, losing the 141 guard.
_harness_exit() {
  local status=$?
  rm -rf "$MOCK_BIN"
  [ -n "${_METRICS_DIR:-}" ] && rm -rf "$_METRICS_DIR"
  [ -n "${_CONFIG_DIR:-}" ] && rm -rf "$_CONFIG_DIR"
  [ -n "${_ADVISORY_TMP:-}" ] && rm -rf "$_ADVISORY_TMP"
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
# Capture comment body files when requested so tests can inspect the rendered
# summary after pr-review-loop.sh removes the temporary file.
if [ -n "${MOCK_GH_BODY_CAPTURE:-}" ]; then
  _gh_body_file=""
  _prev_arg=""
  for _gh_arg in "$@"; do
    if [ "$_prev_arg" = "--body-file" ]; then
      _gh_body_file="$_gh_arg"
      break
    fi
    _prev_arg="$_gh_arg"
  done
  if [ -n "$_gh_body_file" ] && [ -f "$_gh_body_file" ]; then
    cat "$_gh_body_file" > "$MOCK_GH_BODY_CAPTURE"
  fi
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
  *"updatedAt"*)
    printf '%s\n' "${MOCK_GH_UPDATED_AT:-2026-07-18T00:00:00Z}"
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

grep_count_or_zero() {
  local pattern="$1"
  local file="$2"
  local count
  local status

  set +e
  count="$(grep -c -- "$pattern" "$file")"
  status=$?
  set -e

  case "$status" in
    0|1) printf '%s\n' "${count:-0}" ;;
    *) return "$status" ;;
  esac
}

# ---------------------------------------------------------------------------
# Area 0a: project advisory checks hook
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 0a: project advisory checks hook ==="

_ADVISORY_TMP="$(mktemp -d)"

set +e
_default_advisory_output="$(bash "$REPO_ROOT/scripts/development-workflow/run-advisory-checks.sh" 123)"
_default_advisory_status=$?
set -e
run_test "project_advisory_default_stub_exit" "0" "$_default_advisory_status"
run_test "project_advisory_default_stub_empty" "" "$_default_advisory_output"

_marker_script="$_ADVISORY_TMP/marker-advisory.sh"
_marker_file="$_ADVISORY_TMP/marker-count.txt"
_empty_advisory_output_file="$_ADVISORY_TMP/project-advisory-empty.out"
cat > "$_marker_script" <<'EOF_MARKER_ADVISORY'
#!/usr/bin/env bash
printf '%s\n' "${1:-}" >> "$MARKER_FILE"
printf '\n\n**Advisory checks** _(informational - never blocks merge)_\n'
printf -- '- marker ran for PR %s\n' "${1:-}"
EOF_MARKER_ADVISORY
chmod +x "$_marker_script"
MARKER_FILE="$_marker_file" run_project_advisory_checks "" "$_marker_script" >"$_empty_advisory_output_file"
if [ -e "$_marker_file" ]; then
  _empty_pr_invoked="yes"
else
  _empty_pr_invoked="no"
fi
run_test "project_advisory_empty_pr_no_invoke" "no" "$_empty_pr_invoked"
run_test "project_advisory_empty_pr_empty_output" "" "$(cat "$_empty_advisory_output_file")"

_missing_advisory_output="$(run_project_advisory_checks 42 "$_ADVISORY_TMP/missing-advisory.sh")"
run_test "project_advisory_missing_script_empty" "" "$_missing_advisory_output"

_marker_output="$(MARKER_FILE="$_marker_file" run_project_advisory_checks 42 "$_marker_script")"
run_test "project_advisory_marker_invoked_once" "1" "$(wc -l < "$_marker_file" | tr -d ' ')"
run_test "project_advisory_multiline_preserved" "yes" "$(
  if printf '%s\n' "$_marker_output" | grep -q 'marker ran for PR 42'; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

_failing_advisory_script="$_ADVISORY_TMP/failing-advisory.sh"
cat > "$_failing_advisory_script" <<'EOF_FAILING_ADVISORY'
#!/usr/bin/env bash
printf '\n\n**Advisory checks** _(informational - never blocks merge)_\n'
printf -- '- diagnostic preserved\n'
exit 17
EOF_FAILING_ADVISORY
chmod +x "$_failing_advisory_script"
set +e
_failing_advisory_output="$(run_project_advisory_checks 42 "$_failing_advisory_script")"
_failing_advisory_status=$?
set -e
run_test "project_advisory_failure_returns_zero" "0" "$_failing_advisory_status"
run_test "project_advisory_failure_preserves_stdout" "yes" "$(
  if printf '%s\n' "$_failing_advisory_output" | grep -q 'diagnostic preserved'; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

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

_LOCAL_OVERRIDE_DIR="$(mktemp -d)"
cat > "$_LOCAL_OVERRIDE_DIR/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2

review:
  on_draft:
    runner: [codex]
    github: [pr-agent]
  on_ready:
    github: [haystack]
YAML
cat > "$_LOCAL_OVERRIDE_DIR/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  on_draft:
    runner: [cursor]
    github: [pr-agent]
  on_ready:
    github: [bugbot]
YAML
local_override_parsed="$(
  workflow_repo_root() { printf '%s\n' "$_LOCAL_OVERRIDE_DIR"; }
  printf 'runner=%s\n' "$(workflow_config_review_on_draft_runner "$(workflow_config_file)" | paste -sd ',' -)"
  printf 'draft=%s\n' "$(workflow_config_review_on_draft_github "$(workflow_config_file)" | paste -sd ',' -)"
  printf 'ready=%s\n' "$(workflow_config_review_on_ready_github "$(workflow_config_file)" | paste -sd ',' -)"
  printf 'all=%s\n' "$(workflow_config_review_platforms "$(workflow_config_file)" | paste -sd ',' -)"
)"
run_test "local_review_override_applied" $'runner=cursor\ndraft=pr-agent\nready=bugbot\nall=pr-agent,bugbot' "$local_override_parsed"

_TEMP_CONFIG="$(mktemp)"
cat > "$_TEMP_CONFIG" <<'YAML'
schema_version: 2

review:
  on_draft:
    runner: [codex]
    github: [pr-agent]
  on_ready:
    github: [haystack]
YAML
temp_override_parsed="$(
  workflow_repo_root() { printf '%s\n' "$_LOCAL_OVERRIDE_DIR"; }
  WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 workflow_config_review_platforms "$_TEMP_CONFIG" | paste -sd ',' -
)"
run_test "local_review_override_applies_to_temp_config_when_forced" "pr-agent,bugbot" "$temp_override_parsed"

_TEMP_WORKTREE_DIR="$(mktemp -d)"
initiating_override_parsed="$(
  workflow_repo_root() { printf '%s\n' "$_TEMP_WORKTREE_DIR"; }
  WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$_LOCAL_OVERRIDE_DIR" \
    WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 \
    workflow_config_review_platforms "$_TEMP_CONFIG" | paste -sd ',' -
)"
run_test "initiating_local_override_applies_in_temp_worktree" "pr-agent,bugbot" "$initiating_override_parsed"

caller_override_root="$(
  WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$_LOCAL_OVERRIDE_DIR" \
    resolve_local_review_override_root "$_TEMP_WORKTREE_DIR"
)"
run_test "caller_override_root_is_preserved" "$_LOCAL_OVERRIDE_DIR" "$caller_override_root"
rm -rf "$_TEMP_WORKTREE_DIR"
unset _TEMP_WORKTREE_DIR initiating_override_parsed caller_override_root

missing_override_status=0
if WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$_LOCAL_OVERRIDE_DIR/missing" workflow_local_config_file >/dev/null 2>&1; then
  missing_override_status=0
else
  missing_override_status=$?
fi
run_test "unavailable_initiating_override_stops_resolution" "1" "$missing_override_status"

cat > "$_LOCAL_OVERRIDE_DIR/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  on_ready:
    github: []
YAML
local_empty_ready_parsed="$(
  workflow_repo_root() { printf '%s\n' "$_LOCAL_OVERRIDE_DIR"; }
  workflow_config_review_on_ready_github "$(workflow_config_file)" | paste -sd ',' -
)"
run_test "local_review_override_empty_ready_github_applied" "" "$local_empty_ready_parsed"
rm -rf "$_LOCAL_OVERRIDE_DIR"
rm -f "$_TEMP_CONFIG"
unset _LOCAL_OVERRIDE_DIR _TEMP_CONFIG local_override_parsed local_empty_ready_parsed temp_override_parsed

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

_DUP_OVERRIDE_DIR="$(mktemp -d)"
cat > "$_DUP_OVERRIDE_DIR/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  on_draft:
    github: [bugbot]
  on_ready:
    github: [bugbot]
YAML
_DUP_TEMP_CONFIG="$(mktemp)"
cat > "$_DUP_TEMP_CONFIG" <<'YAML'
schema_version: 2

review:
  on_draft:
    github: [pr-agent]
  on_ready:
    github: [haystack]
YAML
duplicate_override_warning="$(
  workflow_repo_root() { printf '%s\n' "$_DUP_OVERRIDE_DIR"; }
  WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 emit_review_lifecycle_duplicate_warnings "$_DUP_TEMP_CONFIG" 2>&1 || true
)"
case "$duplicate_override_warning" in
  *'reviewer "bugbot" in more than one bucket'*) duplicate_override_detected=yes ;;
  *) duplicate_override_detected=no ;;
esac
run_test "duplicate_lifecycle_warning_uses_local_override_for_temp_config" "yes" "$duplicate_override_detected"
rm -rf "$_DUP_OVERRIDE_DIR"
rm -f "$_DUP_TEMP_CONFIG"
unset _DUP_OVERRIDE_DIR _DUP_TEMP_CONFIG duplicate_override_warning duplicate_override_detected

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

if grep -q -- '--ready-phase)' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" \
    && grep -q 'append_ready_phase_platforms "$2"' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"; then
  _ready_phase_flag_parse=1
else
  _ready_phase_flag_parse=0
fi
run_test "ready_phase_flag_parsing_wired" "1" "$_ready_phase_flag_parse"

if grep -q -- '--draft-github-only)' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" \
    && grep -q 'pre_after_clean_only=1' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"; then
  _draft_github_only_flag_parse=1
else
  _draft_github_only_flag_parse=0
fi
run_test "draft_github_only_flag_parsing_wired" "1" "$_draft_github_only_flag_parse"
unset _ready_phase_flag_parse _draft_github_only_flag_parse

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
HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
workflow_repo_root() { printf '%s\n' "${HARNESS_REPO_ROOT:-$REPO_ROOT}"; }

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

# test: run_haystack_review skips draft PRs before invoking haystack-reviewer.sh
_haystack_draft_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
'
export MOCK_GH_OUTPUT="true"
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_haystack_draft_overrides"
  _ec=0
  run_haystack_review "42" "feature/test" "1" "30" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "haystack_skips_draft_pr_result" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "haystack_skips_draft_pr_reason" "REASON=pr-is-draft" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "haystack_skips_draft_pr_exit_code" "0" "$actual_exit"
unset MOCK_GH_OUTPUT _haystack_draft_overrides actual_output actual_exit

# test: run_haystack_review escalates when draft state cannot be determined
_haystack_draft_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
'
export MOCK_GH_OUTPUT=""
export MOCK_GH_EXIT=1
actual_output="$(
  eval "$_haystack_draft_overrides"
  _ec=0
  run_haystack_review "42" "feature/test" "1" "30" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "haystack_draft_state_unavailable_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "haystack_draft_state_unavailable_reason" "REASON=draft-state-unavailable" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "haystack_draft_state_unavailable_exit_code" "2" "$actual_exit"
unset MOCK_GH_OUTPUT MOCK_GH_EXIT _haystack_draft_overrides actual_output actual_exit

# test: run_haystack_review forwards Haystack auth errors from companion script
_haystack_auth_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
'
export MOCK_GH_OUTPUT="false"
_haystack_reviewer_stub="$(mktemp -d)"
mkdir -p "$_haystack_reviewer_stub/scripts/development-workflow"
cat > "$_haystack_reviewer_stub/scripts/development-workflow/haystack-reviewer.sh" <<'HAYSTACK_STUB'
#!/usr/bin/env bash
printf 'RESULT=skipped\nREASON=forbidden\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\nCOMMENT_COUNT=0\n'
exit 3
HAYSTACK_STUB
chmod +x "$_haystack_reviewer_stub/scripts/development-workflow/haystack-reviewer.sh"
workflow_repo_root() { printf "%s\n" "$_haystack_reviewer_stub"; }
actual_output="$(
  eval "$_haystack_auth_overrides"
  _ec=0
  run_haystack_review "42" "feature/test" "1" "30" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "haystack_forwards_auth_reason" "REASON=forbidden" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "haystack_forwards_auth_exit_code" "0" "$actual_exit"
rm -rf "$_haystack_reviewer_stub"
unset MOCK_GH_OUTPUT _haystack_auth_overrides actual_output actual_exit
workflow_repo_root() { printf '%s\n' "${HARNESS_REPO_ROOT:-$REPO_ROOT}"; }

# test: run_haystack_review forwards the terminal file-limit reason and display
_haystack_file_limit_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
'
export MOCK_GH_OUTPUT="false"
_haystack_reviewer_stub="$(mktemp -d)"
mkdir -p "$_haystack_reviewer_stub/scripts/development-workflow"
cat > "$_haystack_reviewer_stub/scripts/development-workflow/haystack-reviewer.sh" <<'HAYSTACK_STUB'
#!/usr/bin/env bash
printf 'RESULT=skipped\n'
printf 'REASON=analysis_skipped_file_limit\n'
printf 'DISPLAY_RESULT=skipped (analysis file limit)\n'
printf 'BLOCKING_COUNT=0\nSUGGESTION_COUNT=0\nCOMMENT_COUNT=0\n'
exit 3
HAYSTACK_STUB
chmod +x "$_haystack_reviewer_stub/scripts/development-workflow/haystack-reviewer.sh"
workflow_repo_root() { printf "%s\n" "$_haystack_reviewer_stub"; }
actual_output="$(
  eval "$_haystack_file_limit_overrides"
  _ec=0
  run_haystack_review "42" "feature/test" "1" "30" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "haystack_file_limit_reason_forwarded" "REASON=analysis_skipped_file_limit" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "haystack_file_limit_display_forwarded" "DISPLAY_RESULT=skipped (analysis file limit)" \
  "$(printf '%s\n' "$actual_output" | grep "^DISPLAY_RESULT=")"
run_test "haystack_file_limit_maps_to_healthy_skip" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "haystack_file_limit_mapping_exit_code" "0" "$actual_exit"
rm -rf "$_haystack_reviewer_stub"
unset MOCK_GH_OUTPUT _haystack_file_limit_overrides actual_output actual_exit
workflow_repo_root() { printf '%s\n' "${HARNESS_REPO_ROOT:-$REPO_ROOT}"; }

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

_platform_output='RESULT=skipped
REASON=analysis_skipped_file_limit
DISPLAY_RESULT=skipped (analysis file limit)'
_prt_display_override="$(kv_value_default DISPLAY_RESULT "$_platform_output" "")"
run_test "summary_file_limit_display_override" "skipped (analysis file limit)" "$_prt_display_override"
run_test "file_limit_skip_compare_verdict" "unavailable" "$(normalize_platform_verdict skipped "$_platform_output")"
unset _platform_output _prt_display_override

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

# Test 10.4: _post_review_summary source renders needs_fixes as active findings.
if grep -qF 'result_line="${blocking} blocking finding(s) require fixes"' \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" \
    && grep -qF 'needs_fixes)' \
      "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"; then
  _needs_fixes_summary_count=1
else
  _needs_fixes_summary_count=0
fi
run_test "summary_needs_fixes_active_findings" "1" "$_needs_fixes_summary_count"
unset _needs_fixes_summary_count

# Test 10.5: main needs_fixes exit branch posts the summary before exiting.
_needs_fixes_case_block="$(awk '
  /^  needs_fixes\)/ {capture=1}
  capture {print}
  capture && /^    ;;/ {exit}
' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
if grep -qF '_post_review_summary "$aggregate_result" "$aggregate_reason"' <<<"$_needs_fixes_case_block" \
    && grep -qF 'exit 1' <<<"$_needs_fixes_case_block"; then
  _needs_fixes_main_summary_count=1
else
  _needs_fixes_main_summary_count=0
fi
run_test "main_needs_fixes_exit_posts_summary" "1" "$_needs_fixes_main_summary_count"
unset _needs_fixes_case_block _needs_fixes_main_summary_count

# Test 10.6: _post_review_summary source renders policy acknowledgement details.
if grep -qF '**Policy acknowledgements:**' \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" \
    && grep -qF 'platform_policy_status_notes' \
      "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"; then
  _policy_status_summary_count=1
else
  _policy_status_summary_count=0
fi
run_test "summary_policy_acknowledgements_section" "1" "$_policy_status_summary_count"
unset _policy_status_summary_count

# Test 10.7: blocking, platform advisory, and project advisory findings remain
# visible in the summary in the required order.
_post_summary_source="$(awk '/^_post_review_summary\(\)/,/^}$/' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
eval "$_post_summary_source"
# shellcheck disable=SC2329 # Invoked indirectly by the eval-loaded function.
repo_slug() { printf "owner/repo\n"; }
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
compare_mode=1
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
compare_verdicts=("coderabbit" "clean")
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
platform_policy_status_notes=()
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
pr_number=42
# shellcheck disable=SC2034 # Read by the eval-loaded _post_review_summary function.
branch_name="fix/42-summary"
if ! _summary_call_log="$(mktemp)"; then
  echo "ERROR: failed to allocate summary call log temp file" >&2
  exit 1
fi
if [ -z "$_summary_call_log" ]; then
  echo "ERROR: mktemp returned an empty summary call log path" >&2
  exit 1
fi
if ! _summary_body_capture="$(mktemp)"; then
  echo "ERROR: failed to allocate summary body capture temp file" >&2
  exit 1
fi
if [ -z "$_summary_body_capture" ]; then
  echo "ERROR: mktemp returned an empty summary body capture path" >&2
  exit 1
fi
export MOCK_GH_CALL_LOG="$_summary_call_log"
export MOCK_GH_BODY_CAPTURE="$_summary_body_capture"
MOCK_GH_EXIT=0
export MOCK_GH_EXIT
MOCK_GH_COMMENTS_OUTPUT='[]'
export MOCK_GH_COMMENTS_OUTPUT
_project_advisory_section="

**Advisory checks** _(informational - never blocks merge)_
- Project-specific note"
_post_review_summary "needs_fixes" "haystack_blocking_findings" "haystack (needs_fixes)" "1" "1" \
  "Rules violation@@@https://github.com/lhpaul/ai-dev-framework-template/pull/952#issuecomment-1" \
  "" "1" "haystack" "1" "0" "" "0" "$_project_advisory_section"
if [ -n "${_summary_body_capture:-}" ] && grep -q "1 blocking finding(s) require fixes" "$_summary_body_capture" \
    && grep -q "Advisory findings (non-blocking):" "$_summary_body_capture" \
    && grep -q "Rules violation" "$_summary_body_capture" \
    && grep -q "Advisory checks" "$_summary_body_capture" \
    && grep -q "Project-specific note" "$_summary_body_capture"; then
  _summary_advisory_split="yes"
else
  _summary_advisory_split="no"
fi
run_test "summary_advisory_split_visible" "yes" "$_summary_advisory_split"
_phase_line="$(grep -n "Ready reviewer phase" "$_summary_body_capture" | cut -d: -f1 | head -1)"
_compare_line="$(grep -n "Compare mode" "$_summary_body_capture" | cut -d: -f1 | head -1)"
_platform_advisory_line="$(grep -n "Advisory findings" "$_summary_body_capture" | cut -d: -f1 | head -1)"
_project_advisory_line="$(grep -n "Advisory checks" "$_summary_body_capture" | cut -d: -f1 | head -1)"
if [ -n "$_phase_line" ] && [ -n "$_compare_line" ] \
    && [ -n "$_platform_advisory_line" ] && [ -n "$_project_advisory_line" ] \
    && [ "$_phase_line" -lt "$_compare_line" ] \
    && [ "$_compare_line" -lt "$_platform_advisory_line" ] \
    && [ "$_platform_advisory_line" -lt "$_project_advisory_line" ]; then
  _summary_project_advisory_order="yes"
else
  _summary_project_advisory_order="no"
fi
run_test "summary_project_advisory_order" "yes" "$_summary_project_advisory_order"
rm -f "$_summary_call_log"
rm -f "$_summary_body_capture"

if ! _summary_read_failed_body_capture="$(mktemp)"; then
  echo "ERROR: failed to allocate read-failure summary body capture temp file" >&2
  exit 1
fi
if [ -z "$_summary_read_failed_body_capture" ]; then
  echo "ERROR: mktemp returned an empty read-failure summary body capture path" >&2
  exit 1
fi
export MOCK_GH_BODY_CAPTURE="$_summary_read_failed_body_capture"
MOCK_GH_EXIT=0
MOCK_GH_COMMENTS_EXIT=1
MOCK_GH_UPDATED_AT="2026-07-18T00:10:00Z"
export MOCK_GH_EXIT MOCK_GH_COMMENTS_EXIT MOCK_GH_UPDATED_AT
_post_review_summary "clean" "" "bugbot (clean)" "0" "0"
if [ -n "${_summary_read_failed_body_capture:-}" ] \
    && grep -q "comment_read_failed" "$_summary_read_failed_body_capture"; then
  _summary_read_failed_history="yes"
else
  _summary_read_failed_history="no"
fi
run_test "summary_comment_read_failure_history_unavailable" "yes" "$_summary_read_failed_history"
rm -f "$_summary_read_failed_body_capture"
unset MOCK_GH_CALL_LOG MOCK_GH_BODY_CAPTURE MOCK_GH_EXIT MOCK_GH_COMMENTS_OUTPUT MOCK_GH_COMMENTS_EXIT MOCK_GH_UPDATED_AT
unset _summary_advisory_split _summary_project_advisory_order _post_summary_source
unset _summary_read_failed_body_capture _summary_read_failed_history
unset _phase_line _compare_line _platform_advisory_line _project_advisory_line
unset -f _post_review_summary
unset compare_mode compare_verdicts platform_policy_status_notes pr_number branch_name

# ---------------------------------------------------------------------------
# Area 10b: reviewer-loop history payload (#1243)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 10b: reviewer-loop history payload ==="

pr_number=42
branch_name="fix/42-history"
unresolved_thread_count=0
late_thread_count=0
MOCK_GH_HEAD_SHA="abc-history-1"
MOCK_GH_UPDATED_AT="2026-07-18T00:00:00Z"
export MOCK_GH_HEAD_SHA MOCK_GH_UPDATED_AT

_history_payload="$(reviewer_loop_history_payload_from_existing "" \
  "clean" "" "bugbot (clean)" "0" "0" "1" "bugbot" "1" "0" "")"
run_test "history_first_entry_schema" "reviewer_loop_history.v1" \
  "$(printf '%s\n' "$_history_payload" | jq -r '.schema')"
run_test "history_first_entry_count" "1" \
  "$(printf '%s\n' "$_history_payload" | jq '(.entries // []) | length')"
run_test "history_first_entry_zero_retries" "0" \
  "$(printf '%s\n' "$_history_payload" | jq '((.entries // []) | length) - 1')"
run_test "history_first_entry_result" "clean" \
  "$(printf '%s\n' "$_history_payload" | jq -r '.entries[0].result')"

_history_existing_body="$(cat <<EOF_HISTORY
### Automated Reviewer Loop Summary

*Posted automatically by \`pr-review-loop.sh\`.*

<details>
<summary>Reviewer-loop history (1 iteration)</summary>

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_history_payload" | jq '.')
\`\`\`
</details>
EOF_HISTORY
)"
MOCK_GH_HEAD_SHA="abc-history-2"
MOCK_GH_UPDATED_AT="2026-07-18T00:05:00Z"
_history_payload_2="$(reviewer_loop_history_payload_from_existing "$_history_existing_body" \
  "needs_fixes" "unresolved_review_threads" "bugbot (needs_fixes)" "1" "0" "1" "bugbot" "1" "1" "review_threads")"
run_test "history_append_entry_count" "2" \
  "$(printf '%s\n' "$_history_payload_2" | jq '(.entries // []) | length')"
run_test "history_append_second_iteration" "2" \
  "$(printf '%s\n' "$_history_payload_2" | jq '.entries[1].iteration')"
run_test "history_append_preserves_first_result" "clean" \
  "$(printf '%s\n' "$_history_payload_2" | jq -r '.entries[0].result')"
run_test "history_append_records_blocking_count" "1" \
  "$(printf '%s\n' "$_history_payload_2" | jq '.entries[1].blocking_count')"

_history_empty_entries_body=$'### Automated Reviewer Loop Summary\n\n<!-- reviewer-loop-history:v1 -->\n```json\n{\"schema\":\"reviewer_loop_history.v1\",\"history_status\":\"available\",\"entries\":[]}\n```\n'
_history_empty_entries_payload="$(reviewer_loop_history_payload_from_existing "$_history_empty_entries_body" \
  "clean" "" "bugbot (clean)" "0" "0")"
run_test "history_empty_entries_append_count" "1" \
  "$(printf '%s\n' "$_history_empty_entries_payload" | jq '(.entries // []) | length')"

_history_needs_rerun_payload="$(reviewer_loop_history_payload_from_existing "" \
  "needs_rerun" "" "pr-agent (needs_rerun)" "0" "0")"
run_test "history_needs_rerun_result" "needs_rerun" \
  "$(printf '%s\n' "$_history_needs_rerun_payload" | jq -r '.entries[0].result')"

_history_same_sha_body="$(cat <<EOF_HISTORY_SAME_SHA
### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_history_payload" | jq '.')
\`\`\`
EOF_HISTORY_SAME_SHA
)"
MOCK_GH_HEAD_SHA="abc-history-1"
_history_same_sha_payload="$(reviewer_loop_history_payload_from_existing "$_history_same_sha_body" \
  "clean" "transient_retry" "bugbot (clean)" "0" "0")"
run_test "history_same_sha_duplicate_appends" "2" \
  "$(printf '%s\n' "$_history_same_sha_payload" | jq '(.entries // []) | length')"

_history_file_limit_payload="$(reviewer_loop_history_payload_from_existing "" \
  "clean" "" "pr-agent (clean), haystack (skipped (analysis file limit))" "0" "0")"
run_test "history_file_limit_platform_display" "haystack (skipped (analysis file limit))" \
  "$(printf '%s\n' "$_history_file_limit_payload" | jq -r '.entries[0].platforms[] | select(startswith("haystack "))')"
_history_file_limit_body="$(cat <<EOF_HISTORY_FILE_LIMIT
### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_history_file_limit_payload" | jq '.')
\`\`\`
EOF_HISTORY_FILE_LIMIT
)"
_history_file_limit_rerun="$(reviewer_loop_history_payload_from_existing "$_history_file_limit_body" \
  "clean" "" "pr-agent (clean), haystack (skipped (analysis file limit))" "0" "0")"
run_test "history_file_limit_same_head_rerun_appends" "2" \
  "$(printf '%s\n' "$_history_file_limit_rerun" | jq '(.entries // []) | length')"

_history_latest_body="$(cat <<EOF_HISTORY_LATEST
### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
{"schema":"reviewer_loop_history.v1","history_status":"available","entries":[{"iteration":1,"result":"old"}]}
\`\`\`

Some adjacent Markdown that must not be consumed.

<!-- reviewer-loop-history:v1 -->
\`\`\`json
{"schema":"reviewer_loop_history.v1","history_status":"available","entries":[{"iteration":1,"result":"latest"}]}
\`\`\`
Trailing summary text.
EOF_HISTORY_LATEST
)"
_history_latest_payload="$(reviewer_loop_history_payload_from_existing "$_history_latest_body" \
  "clean" "" "bugbot (clean)" "0" "0")"
run_test "history_latest_block_preserved" "latest" \
  "$(printf '%s\n' "$_history_latest_payload" | jq -r '.entries[0].result')"
run_test "history_fence_boundary_append_count" "2" \
  "$(printf '%s\n' "$_history_latest_payload" | jq '(.entries // []) | length')"

_history_summary_comments="$(cat <<EOF_HISTORY_COMMENTS
[
  {
    "id": 101,
    "created_at": "2026-07-18T00:00:00Z",
    "body": "### Automated Reviewer Loop Summary\n\n*Posted automatically by \`pr-review-loop.sh\`.*\n\n<!-- reviewer-loop-history:v1 -->\n\`\`\`json\n{\"schema\":\"reviewer_loop_history.v1\",\"history_status\":\"available\",\"entries\":[{\"iteration\":1,\"result\":\"needs_fixes\"}]}\n\`\`\`"
  },
  {
    "id": 102,
    "created_at": "2026-07-18T00:05:00Z",
    "body": "### Automated Reviewer Loop Summary\n\n*Posted automatically by \`pr-review-loop.sh\`.*\n\n<!-- reviewer-loop-history:v1 -->\n\`\`\`json\n{\"schema\":\"reviewer_loop_history.v1\",\"history_status\":\"unavailable\",\"history_unavailable_reason\":\"comment_read_failed\",\"entries\":[]}\n\`\`\`"
  }
]
EOF_HISTORY_COMMENTS
)"
_history_selected_record="$(printf '%s\n' "$_history_summary_comments" | reviewer_loop_history_select_summary_record)"
run_test "history_selector_targets_newest_comment" "102" \
  "$(printf '%s\n' "$_history_selected_record" | jq '.id')"
run_test "history_selector_preserves_available_history" "needs_fixes" \
  "$(printf '%s\n' "$_history_selected_record" | jq -r '.body' | reviewer_loop_history_extract_latest_json | jq -r '.entries[0].result')"

_history_malformed_body=$'### Automated Reviewer Loop Summary\n\n<!-- reviewer-loop-history:v1 -->\n```json\n{ not json\n```\n'
_history_malformed_payload="$(reviewer_loop_history_payload_from_existing "$_history_malformed_body" \
  "clean" "" "bugbot (clean)" "0" "0")"
run_test "history_malformed_unavailable" "unavailable" \
  "$(printf '%s\n' "$_history_malformed_payload" | jq -r '.history_status')"
run_test "history_malformed_reason" "malformed_history" \
  "$(printf '%s\n' "$_history_malformed_payload" | jq -r '.history_unavailable_reason')"

_history_wrong_schema_body=$'### Automated Reviewer Loop Summary\n\n<!-- reviewer-loop-history:v1 -->\n```json\n{\"schema\":\"other.v1\",\"entries\":[]}\n```\n'
_history_wrong_schema_payload="$(reviewer_loop_history_payload_from_existing "$_history_wrong_schema_body" \
  "clean" "" "bugbot (clean)" "0" "0")"
run_test "history_wrong_schema_reason" "unknown_schema" \
  "$(printf '%s\n' "$_history_wrong_schema_payload" | jq -r '.history_unavailable_reason')"

_history_prior_unavailable_body=$'### Automated Reviewer Loop Summary\n\n<!-- reviewer-loop-history:v1 -->\n```json\n{\"schema\":\"reviewer_loop_history.v1\",\"history_status\":\"unavailable\",\"history_unavailable_reason\":\"comment_read_failed\",\"entries\":[]}\n```\n'
_history_prior_unavailable_payload="$(reviewer_loop_history_payload_from_existing "$_history_prior_unavailable_body" \
  "clean" "" "bugbot (clean)" "0" "0")"
run_test "history_prior_unavailable_preserved" "comment_read_failed" \
  "$(printf '%s\n' "$_history_prior_unavailable_payload" | jq -r '.history_unavailable_reason')"

_history_read_failed_body="$(reviewer_loop_history_unavailable_stub_body comment_read_failed)"
_history_read_failed_payload="$(reviewer_loop_history_payload_from_existing "$_history_read_failed_body" \
  "clean" "" "bugbot (clean)" "0" "0")"
run_test "history_read_failure_unavailable" "unavailable" \
  "$(printf '%s\n' "$_history_read_failed_payload" | jq -r '.history_status')"
run_test "history_read_failure_reason" "comment_read_failed" \
  "$(printf '%s\n' "$_history_read_failed_payload" | jq -r '.history_unavailable_reason')"

_history_rendered_section="$(reviewer_loop_history_render_section "$_history_payload_2")"
if printf '%s\n' "$_history_rendered_section" | grep -qF "$REVIEWER_LOOP_HISTORY_MARKER" \
    && printf '%s\n' "$_history_rendered_section" | grep -qF "Reviewer-loop history (2 iterations)"; then
  _history_rendered_ok="yes"
else
  _history_rendered_ok="no"
fi
run_test "history_rendered_section" "yes" "$_history_rendered_ok"

unset _history_payload _history_existing_body _history_payload_2
unset _history_empty_entries_body _history_empty_entries_payload
unset _history_needs_rerun_payload
unset _history_same_sha_body _history_same_sha_payload
unset _history_file_limit_payload _history_file_limit_body _history_file_limit_rerun
unset _history_latest_body _history_latest_payload
unset _history_summary_comments _history_selected_record
unset _history_malformed_body _history_malformed_payload
unset _history_wrong_schema_body _history_wrong_schema_payload
unset _history_prior_unavailable_body _history_prior_unavailable_payload
unset _history_read_failed_body _history_read_failed_payload
unset _history_rendered_section _history_rendered_ok
unset MOCK_GH_HEAD_SHA MOCK_GH_UPDATED_AT
unset pr_number branch_name unresolved_thread_count late_thread_count

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
if ! _call_log_11="$(mktemp)"; then
  echo "ERROR: failed to allocate regression-label test temp file" >&2
  exit 1
fi
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
if ! _call_log_11="$(mktemp)"; then
  echo "ERROR: failed to allocate regression-label test temp file" >&2
  exit 1
fi
export MOCK_GH_OUTPUT="true"
export MOCK_GH_CALL_LOG="$_call_log_11"
restore_regression_label_if_missing "42" "feature/42-my-feature" 2>/dev/null
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_already_present_no_gh_edit" "0" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG

# Test 11.3: non-implementation branch (spec/) → NO gh pr edit regardless of
# label state or summary-comment presence.
if ! _call_log_11="$(mktemp)"; then
  echo "ERROR: failed to allocate regression-label test temp file" >&2
  exit 1
fi
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
if ! _call_log_11="$(mktemp)"; then
  echo "ERROR: failed to allocate regression-label test temp file" >&2
  exit 1
fi
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
if ! _call_log_11="$(mktemp)"; then
  echo "ERROR: failed to allocate regression-label test temp file" >&2
  exit 1
fi
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
run_test "reviewer_failed_skipped_file_limit" "no" "$(_reviewer_failed_required skipped analysis_skipped_file_limit)"
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

_codex_trigger_comments='[
  {
    "id": 111,
    "created_at": "2026-01-01T00:00:00Z",
    "user": {"login": "alice"},
    "body": "Review triggered by workflow runner for abc123"
  },
  {
    "id": 222,
    "created_at": "2026-01-01T00:05:00Z",
    "user": {"login": "bob"},
    "body": "Review triggered by workflow runner for abc123"
  },
  {
    "id": 333,
    "created_at": "2026-01-01T00:10:00Z",
    "user": {"login": "chatgpt-codex-connector[bot]"},
    "body": "Review triggered by workflow runner for abc123"
  }
]'
_codex_selected_trigger="$(
  printf '%s\n' "$_codex_trigger_comments" \
    | jq -sc --arg sha "abc123" --arg marker "review triggered by workflow runner" --arg bot "chatgpt-codex-connector[bot]" --arg bot_plain "chatgpt-codex-connector" \
      '[.[][] | select(.user.login != $bot and .user.login != $bot_plain) | select((.body | contains($sha)) and (.body | ascii_downcase | contains($marker)))] | sort_by(.created_at) | reverse | .[0] // empty | {id: .id, created_at: .created_at, body: .body}'
)"
run_test "codex_trigger_idempotency_selects_newest" "222" \
  "$(printf '%s\n' "$_codex_selected_trigger" | jq -r '.id')"
run_test "codex_trigger_idempotency_single_object" "1" \
  "$(printf '%s\n' "$_codex_selected_trigger" | wc -l | tr -d ' ')"
_codex_paginated_trigger_comments='[
  {
    "id": 111,
    "created_at": "2026-01-01T00:00:00Z",
    "user": {"login": "alice"},
    "body": "Review triggered by workflow runner for abc123"
  }
]
[
  {
    "id": 222,
    "created_at": "2026-01-01T00:05:00Z",
    "user": {"login": "bob"},
    "body": "Review triggered by workflow runner for abc123"
  }
]'
_codex_paginated_selected_trigger="$(
  printf '%s\n' "$_codex_paginated_trigger_comments" \
    | jq -sc --arg sha "abc123" --arg marker "review triggered by workflow runner" --arg bot "chatgpt-codex-connector[bot]" --arg bot_plain "chatgpt-codex-connector" \
      '[.[][] | select(.user.login != $bot and .user.login != $bot_plain) | select((.body | contains($sha)) and (.body | ascii_downcase | contains($marker)))] | sort_by(.created_at) | reverse | .[0] // empty | {id: .id, created_at: .created_at, body: .body}'
)"
run_test "codex_trigger_idempotency_paginated_selects_newest" "222" \
  "$(printf '%s\n' "$_codex_paginated_selected_trigger" | jq -r '.id')"
run_test "codex_trigger_idempotency_paginated_single_object" "1" \
  "$(printf '%s\n' "$_codex_paginated_selected_trigger" | wc -l | tr -d ' ')"
unset _codex_trigger_comments _codex_selected_trigger _codex_paginated_trigger_comments _codex_paginated_selected_trigger

_codex_usage_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_usage_comment_mock_dir/gh" <<'CODEX_USAGE_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcusage1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":101,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":201,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"You have reached your Codex usage limits for code reviews."}]\n'
    exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
CODEX_USAGE_COMMENT_GH
chmod +x "$_codex_usage_comment_mock_dir/gh"

_codex_usage_comment_output=""
_codex_usage_comment_exit=0
PATH="$_codex_usage_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_usage_comment_mock_dir/output.txt" 2>&1 || _codex_usage_comment_exit=$?
_codex_usage_comment_output="$(cat "$_codex_usage_comment_mock_dir/output.txt")"
run_test "codex_usage_limit_comment_exit_unavailable" "3" "$_codex_usage_comment_exit"
run_test "codex_usage_limit_comment_reason" "REASON=codex-github-usage-limit" \
  "$(printf '%s\n' "$_codex_usage_comment_output" | grep "^REASON=")"
rm -rf "$_codex_usage_comment_mock_dir"
unset _codex_usage_comment_mock_dir _codex_usage_comment_output _codex_usage_comment_exit

_codex_usage_review_mock_dir="$(mktemp -d)"
cat > "$_codex_usage_review_mock_dir/gh" <<'CODEX_USAGE_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcreview1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":102,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex review capacity exhausted. Please rerun after quota reset."}]\n'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
CODEX_USAGE_REVIEW_GH
chmod +x "$_codex_usage_review_mock_dir/gh"

_codex_usage_review_output=""
_codex_usage_review_exit=0
PATH="$_codex_usage_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_usage_review_mock_dir/output.txt" 2>&1 || _codex_usage_review_exit=$?
_codex_usage_review_output="$(cat "$_codex_usage_review_mock_dir/output.txt")"
run_test "codex_usage_limit_review_exit_unavailable" "3" "$_codex_usage_review_exit"
run_test "codex_usage_limit_review_reason" "REASON=codex-github-usage-limit" \
  "$(printf '%s\n' "$_codex_usage_review_output" | grep "^REASON=")"
rm -rf "$_codex_usage_review_mock_dir"
unset _codex_usage_review_mock_dir _codex_usage_review_output _codex_usage_review_exit

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
  check_unresolved_threads() { printf "0\n"; return 0; }
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
run_test "codex_usage_limit_loop_blocking_zero" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "codex_usage_limit_loop_exit_code" "2" "$actual_exit"
rm -rf "$_codex_usage_loop_tmp"
unset _codex_usage_loop_tmp _codex_overrides actual_output actual_exit

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
# Area 14: _check_release_pr_guard — release PR early-exit guard (#960)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 14: _check_release_pr_guard ==="

# Helper: set MOCK_GH_OUTPUT to simulate a gh pr view JSON response.
# MOCK_GH_OUTPUT is the default gh mock output used when no specific case
# applies (the default case in the mock gh script).
# For tests that pass --branch, the head is known; only the base is fetched.

# Test 14.1: release/* head branch detected as release PR (branch provided)
# When branch is provided, no gh call is made; mock output is irrelevant.
export MOCK_GH_OUTPUT='[]'
_guard_out=""
_guard_exit=0
_guard_out="$(_check_release_pr_guard "100" "release/v1.0.0")" || _guard_exit=$?
run_test "release_guard_release_head_fires" "RELEASE_GUARD_FIRED=1" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_release_head_exit0" "0" "$_guard_exit"

# Test 14.2: hotfix/* head branch detected as release PR (branch provided)
_guard_out=""
_guard_exit=0
_guard_out="$(_check_release_pr_guard "101" "hotfix/v1.0.1")" || _guard_exit=$?
run_test "release_guard_hotfix_head_fires" "RELEASE_GUARD_FIRED=1" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_hotfix_head_exit0" "0" "$_guard_exit"

# Test 14.3: develop-targeting feature branch — guard does NOT fire
_guard_out=""
_guard_exit=1
_guard_out="$(_check_release_pr_guard "103" "feature/some-feature")" || _guard_exit=$?
run_test "release_guard_feature_no_fire" "RELEASE_GUARD_FIRED=0" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_feature_exit1" "1" "$_guard_exit"

# Test 14.4: fix/* branch — guard does NOT fire
_guard_out=""
_guard_exit=1
_guard_out="$(_check_release_pr_guard "104" "fix/some-fix")" || _guard_exit=$?
run_test "release_guard_fix_no_fire" "RELEASE_GUARD_FIRED=0" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"

# Test 14.5: no --branch provided; head branch fetched from PR, parsed via jq.
# The mock returns MOCK_GH_OUTPUT for the default gh pr view call. The function
# now calls gh pr view WITHOUT --jq and then pipes to jq itself, so the mock
# must return valid JSON rather than a pre-filtered plain branch name.
export MOCK_GH_OUTPUT='{"headRefName":"release/v2.0.0"}'
_guard_out=""
_guard_exit=0
_guard_out="$(_check_release_pr_guard "105")" || _guard_exit=$?
run_test "release_guard_fetched_head_fires" "RELEASE_GUARD_FIRED=1" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_fetched_head_value" "RELEASE_GUARD_HEAD=release/v2.0.0" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_HEAD=")"
export MOCK_GH_OUTPUT='[]'

# Test 14.6: no --branch provided; gh pr view failure — guard does not fire.
# Fail-safe design: a SKIP guard that can't determine the branch defaults to
# NOT firing, so the reviewer loop runs normally (fail-open is safe here).
export MOCK_GH_EXIT=1
export MOCK_GH_OUTPUT=''
_guard_out=""
_guard_exit=1
_guard_out="$(_check_release_pr_guard "106")" || _guard_exit=$?
run_test "release_guard_fetch_failure_no_fire" "RELEASE_GUARD_FIRED=0" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_fetch_failure_exit1" "1" "$_guard_exit"
unset MOCK_GH_EXIT
export MOCK_GH_OUTPUT='[]'

# Test 14.7: no --branch provided; gh succeeds but jq parse fails (malformed
# JSON) — guard does not fire (fail-safe).
export MOCK_GH_OUTPUT='not-valid-json'
_guard_out=""
_guard_exit=1
_guard_out="$(_check_release_pr_guard "107")" || _guard_exit=$?
run_test "release_guard_jq_parse_fail_no_fire" "RELEASE_GUARD_FIRED=0" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_jq_parse_fail_exit1" "1" "$_guard_exit"
export MOCK_GH_OUTPUT='[]'

# Test 14.8: no --branch provided; gh succeeds with null headRefName field —
# guard does not fire (null collapses to empty string via jq // "").
export MOCK_GH_OUTPUT='{"headRefName":null}'
_guard_out=""
_guard_exit=1
_guard_out="$(_check_release_pr_guard "108")" || _guard_exit=$?
run_test "release_guard_null_head_no_fire" "RELEASE_GUARD_FIRED=0" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_null_head_exit1" "1" "$_guard_exit"
export MOCK_GH_OUTPUT='[]'

unset _guard_out _guard_exit

# ---------------------------------------------------------------------------
# Area 15: main-loop integration — release guard in full-script execution
# ---------------------------------------------------------------------------
# The harness-mode early-return prevents the Area 14 function tests from
# exercising the main-loop code that calls _check_release_pr_guard (lines
# 4127–4163 in pr-review-loop.sh). These integration tests run the full
# script as a subprocess with a mocked gh so the main-loop path is covered.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 15: main-loop integration — release guard ==="

_integration_mock_bin="$(mktemp -d)"
_integration_cleanup() { rm -rf "${_integration_mock_bin:-}"; }
trap '_integration_cleanup' EXIT

# Minimal mock gh for the integration tests:
#  - headRefName queries: return INTEG_MOCK_HEAD_JSON
#  - pr edit (sync_reviewer_failed_label): succeed silently
#  - everything else: succeed silently
cat > "$_integration_mock_bin/gh" <<'INTEG_GH_MOCK'
#!/usr/bin/env bash
[ -n "${INTEG_MOCK_GH_LOG:-}" ] && printf '%s\n' "$*" >> "$INTEG_MOCK_GH_LOG"
case "$*" in
  *"headRefName"*)
    # Use a variable for the default to avoid the bash brace-balance issue:
    # ${VAR:-{"key":""}} closes ${...} at the inner }, producing a stray }
    # in the output and therefore invalid JSON.
    _hdr_default='{"headRefName":""}'
    printf '%s\n' "${INTEG_MOCK_HEAD_JSON:-$_hdr_default}"
    exit 0
    ;;
  pr\ comment\ *)
    if [ "${INTEG_MOCK_PR_COMMENT_FAIL:-0}" = "1" ]; then
      printf 'mock pr comment failure\n' >&2
      exit 64
    fi
    exit 0
    ;;
  *"pr edit"*|*"api"*|*"pr view"*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
INTEG_GH_MOCK
chmod +x "$_integration_mock_bin/gh"

_run_loop_integration() {
  # Run pr-review-loop.sh as a subprocess with the integration mock in PATH.
  # Captures combined stdout; ignores stderr (diagnostic messages).
  PATH="$_integration_mock_bin:$PATH" \
    bash "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" "$@" 2>/dev/null
}

# Test 15.1: release/* head branch → main loop emits RESULT=skipped, REASON=release_pr, exits 0
export INTEG_MOCK_HEAD_JSON='{"headRefName":"release/v9.9.9"}'
_integ_gh_log="$(mktemp)"
export INTEG_MOCK_GH_LOG="$_integ_gh_log"
_integ_out=""
_integ_exit=0
set +e
_integ_out="$(_run_loop_integration 999)"
_integ_exit=$?
set -e
run_test "mainloop_release_guard_result_skipped" "RESULT=skipped" \
  "$(printf '%s\n' "$_integ_out" | grep '^RESULT=')"
run_test "mainloop_release_guard_reason_release_pr" "REASON=release_pr" \
  "$(printf '%s\n' "$_integ_out" | grep '^REASON=')"
run_test "mainloop_release_guard_exit0" "0" "$_integ_exit"
run_test "mainloop_release_guard_posts_summary" "1" "$(
  grep -c -- 'pr comment 999 --body-file' "$_integ_gh_log" 2>/dev/null || true
)"
rm -f "$_integ_gh_log"
unset INTEG_MOCK_GH_LOG
unset INTEG_MOCK_HEAD_JSON

# Test 15.1b: release guard escalates if it cannot post the required summary marker
export INTEG_MOCK_HEAD_JSON='{"headRefName":"release/v9.9.10"}'
export INTEG_MOCK_PR_COMMENT_FAIL=1
_integ_out=""
_integ_exit=0
set +e
_integ_out="$(_run_loop_integration 997)"
_integ_exit=$?
set -e
run_test "mainloop_release_guard_comment_failure_result" "RESULT=escalate" \
  "$(printf '%s\n' "$_integ_out" | grep '^RESULT=' | tail -1)"
run_test "mainloop_release_guard_comment_failure_reason" "REASON=release_guard_summary_failed" \
  "$(printf '%s\n' "$_integ_out" | grep '^REASON=' | tail -1)"
run_test "mainloop_release_guard_comment_failure_single_result" "1" \
  "$(printf '%s\n' "$_integ_out" | grep -c '^RESULT=')"
run_test "mainloop_release_guard_comment_failure_exit1" "1" "$_integ_exit"
unset INTEG_MOCK_PR_COMMENT_FAIL
unset INTEG_MOCK_HEAD_JSON

# Test 15.2: hotfix/* head branch → main loop also emits RESULT=skipped, exits 0
export INTEG_MOCK_HEAD_JSON='{"headRefName":"hotfix/v9.9.1"}'
_integ_gh_log="$(mktemp)"
export INTEG_MOCK_GH_LOG="$_integ_gh_log"
_integ_out=""
_integ_exit=0
set +e
_integ_out="$(_run_loop_integration 998)"
_integ_exit=$?
set -e
run_test "mainloop_hotfix_guard_result_skipped" "RESULT=skipped" \
  "$(printf '%s\n' "$_integ_out" | grep '^RESULT=')"
run_test "mainloop_hotfix_guard_exit0" "0" "$_integ_exit"
run_test "mainloop_hotfix_guard_posts_summary" "1" "$(
  grep -c -- 'pr comment 998 --body-file' "$_integ_gh_log" 2>/dev/null || true
)"
rm -f "$_integ_gh_log"
unset INTEG_MOCK_GH_LOG
unset INTEG_MOCK_HEAD_JSON

# Test 15.3: --branch release/v9.9.9 flag → guard fires without a gh call, exits 0
_integ_out=""
_integ_exit=0
set +e
_integ_out="$(_run_loop_integration 997 --branch release/v9.9.9)"
_integ_exit=$?
set -e
run_test "mainloop_branch_flag_release_result_skipped" "RESULT=skipped" \
  "$(printf '%s\n' "$_integ_out" | grep '^RESULT=')"
run_test "mainloop_branch_flag_release_exit0" "0" "$_integ_exit"

_integration_cleanup
unset _integ_out _integ_exit INTEG_MOCK_HEAD_JSON

# ---------------------------------------------------------------------------
# Area 16: run_bugbot_review() — exit-code and key-value output contract (AC-9)
#
# Tests cover:
#   16.0a bot_login_for_platform returns "cursor[bot]" by default for bugbot
#   16.0b bot_login_for_platform respects BUGBOT_BOT_LOGIN env override
#   16.1  clean path: check run completes with conclusion=success, no blocking
#         comments → RESULT=clean, exit 0
#   16.2  needs_fixes path: check run completes with conclusion=failure, blocking
#         cursor[bot] review body → RESULT=needs_fixes, exit 1
#   16.3  escalate (timeout) path: check run in_progress, budget exhausted with
#         check_appeared=1 → RESULT=escalate, REASON=timeout, exit 2
#   16.4  escalate (unavailable) path: no check run appears within budget
#         (check_appeared=0) → RESULT=escalate, REASON=unavailable, exit 2
#   16.5  escalate (head-sha-unavailable): pulls API returns empty head SHA
#         → RESULT=escalate, REASON=head-sha-unavailable, exit 2
#   16.6  idempotency fast-path: existing blocking cursor[bot] finding on HEAD
#         → RESULT=needs_fixes REASON=existing_findings, exit 1 (no trigger POST)
#   16.7  trigger-failed path: trigger comment POST fails
#         → RESULT=escalate REASON=trigger-failed, exit 2
#   16.8  fetch-failed path: check-run API call fails during Phase 3 poll
#         → RESULT=escalate REASON=fetch-failed, exit 2
#   16.8b fetch-failed path: check-run API call fails during Phase 2 trigger guard
#         → RESULT=escalate REASON=fetch-failed, exit 2
#   16.8c fetch-failed path: check-run JSON parse fails during Phase 2 trigger guard
#         → RESULT=escalate REASON=fetch-failed, exit 2
#   16.9  neutral conclusion path: check run concludes neutral
#         → RESULT=clean BLOCKING_COUNT=0 SUGGESTION_COUNT=0, exit 0
#   16.10 run_platform_review routes "bugbot" to run_bugbot_review
#
# Each test that exercises run_bugbot_review requires a custom gh mock because
# the function issues several incompatible gh API call shapes in a single run
# (pulls API, commits API, check-runs API, PR comments API, reviews API).  The
# per-test custom mock is written to a temp directory and placed on PATH before
# calling run_bugbot_review.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 16: run_bugbot_review — clean / needs_fixes / escalate ==="

# Helper overrides injected into every run_bugbot_review subshell.
_bugbot_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  _interruptible_sleep() { :; }
'

# ---------------------------------------------------------------------------
# Test 16.0a: bot_login_for_platform returns "cursor[bot]" for bugbot (default)
# ---------------------------------------------------------------------------
unset BUGBOT_BOT_LOGIN
actual="$(bot_login_for_platform "bugbot")"
run_test "bugbot_bot_login_default" "cursor[bot]" "$actual"

# ---------------------------------------------------------------------------
# Test 16.0b: bot_login_for_platform respects BUGBOT_BOT_LOGIN env override
# ---------------------------------------------------------------------------
export BUGBOT_BOT_LOGIN="my-custom-bugbot[bot]"
actual="$(bot_login_for_platform "bugbot")"
run_test "bugbot_bot_login_env_override" "my-custom-bugbot[bot]" "$actual"
unset BUGBOT_BOT_LOGIN

# ---------------------------------------------------------------------------
# Test 16.0c-d: Bugbot clean summary detection must not hide finding markers
# ---------------------------------------------------------------------------
bugbot_clean_body="Cursor Bugbot found no new issues in this pull request."
if is_bugbot_clean_review "$bugbot_clean_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_clean_phrase_is_non_blocking" "clean" "$actual"

bugbot_current_clean_body=$'<!-- BUGBOT_REVIEW -->\n✅ Bugbot reviewed your changes and found no new issues!\n\n_Comment `@cursor review` or `bugbot run` to trigger another review on this PR_\n\n<sup>Reviewed by [Cursor Bugbot](https://cursor.com/bugbot) for commit a195d26744760a2060cc934596779c821394ba21. Configure [here](https://www.cursor.com/dashboard/bugbot).</sup>'
if is_bugbot_clean_review "$bugbot_current_clean_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_current_clean_review_is_non_blocking" "clean" "$actual"

bugbot_current_mixed_body="$bugbot_current_clean_body"$'\n\n**Medium Severity**\n\n<!-- BUGBOT_BUG_ID: abc123 -->'
if is_bugbot_clean_review "$bugbot_current_mixed_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_current_finding_markers_override_clean_phrase" "blocking" "$actual"

bugbot_mixed_body=$'Cursor Bugbot found no issues in this pull request.\n\n**High Severity**\n\n<!-- BUGBOT_BUG_ID: abc123 -->'
if is_bugbot_clean_review "$bugbot_mixed_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_finding_markers_override_clean_phrase" "blocking" "$actual"

bugbot_multiline_body=$'Cursor Bugbot found no issues in this pull request.\n\nThis review still describes a blocking workflow problem.'
if is_bugbot_clean_review "$bugbot_multiline_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_clean_phrase_in_multiline_body_is_blocking" "blocking" "$actual"

bugbot_same_line_severity_body="Cursor Bugbot found no issues in this pull request. **High Severity**: still broken"
if is_bugbot_clean_review "$bugbot_same_line_severity_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_same_line_severity_is_blocking" "blocking" "$actual"

bugbot_same_line_mixed_body="Cursor Bugbot found no issues in this pull request, but the reviewer loop still drops blocking findings."
if is_bugbot_clean_review "$bugbot_same_line_mixed_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_same_line_mixed_phrase_is_blocking" "blocking" "$actual"
unset bugbot_clean_body bugbot_current_clean_body bugbot_current_mixed_body bugbot_mixed_body bugbot_multiline_body bugbot_same_line_severity_body bugbot_same_line_mixed_body actual

if is_bugbot_disabled_message "Bugbot is disabled for this repository."; then
  actual="disabled"
else
  actual="active"
fi
run_test "bugbot_disabled_message_detected" "disabled" "$actual"

if is_bugbot_disabled_message "Cursor Bugbot found no issues in this pull request."; then
  actual="disabled"
else
  actual="active"
fi
run_test "bugbot_clean_phrase_not_disabled" "active" "$actual"

if is_bugbot_disabled_message "This repository setting is disabled for this repository in general."; then
  actual="disabled"
else
  actual="active"
fi
run_test "bugbot_generic_disabled_phrase_not_matched" "active" "$actual"

if is_bugbot_usage_limit_message "Bugbot couldn't run - usage limit reached"; then
  actual="usage_limit"
else
  actual="active"
fi
run_test "bugbot_usage_limit_message_detected" "usage_limit" "$actual"

if is_bugbot_usage_limit_message "Bugbot could not run: usage/spend limit reached"; then
  actual="usage_limit"
else
  actual="active"
fi
run_test "bugbot_usage_spend_slash_message_detected" "usage_limit" "$actual"

if is_bugbot_usage_limit_message "Bugbot could not run: usage/spend-limit reached"; then
  actual="usage_limit"
else
  actual="active"
fi
run_test "bugbot_usage_spend_hyphen_message_detected" "usage_limit" "$actual"

if is_bugbot_usage_limit_message "Cursor Bugbot found no issues in this pull request."; then
  actual="usage_limit"
else
  actual="active"
fi
run_test "bugbot_clean_phrase_not_usage_limit" "active" "$actual"

bugbot_explicit_skip_body="Skipping Bugbot: your auto mode classified this PR to skip. Visit the Bugbot dashboard to update your settings."
if is_bugbot_explicit_skip_message "$bugbot_explicit_skip_body"; then
  actual="explicit_skip"
else
  actual="active"
fi
run_test "bugbot_explicit_skip_message_detected" "explicit_skip" "$actual"

if is_bugbot_explicit_skip_message "Cursor Bugbot found no issues in this pull request."; then
  actual="explicit_skip"
else
  actual="active"
fi
run_test "bugbot_clean_phrase_not_explicit_skip" "active" "$actual"
unset bugbot_explicit_skip_body actual

# ---------------------------------------------------------------------------
# Test 16.1: clean path — check run conclusion=success, no blocking comments
# ---------------------------------------------------------------------------
_bugbot_mock_dir_161="$(mktemp -d)"
cat > "$_bugbot_mock_dir_161/gh" <<'BUGBOT_GH_161'
#!/usr/bin/env bash
case "$*" in
  # pulls API — head SHA resolution
  *"--jq .head.sha"*)
    printf 'abc161sha\n'; exit 0 ;;
  # commit timestamp resolution
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  # trigger comment POST
  *"--method POST"*)
    exit 0 ;;
  # existing inline comments (Phase 1 and Phase 3 success path): no cursor[bot] comments
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  # existing reviews (Phase 1): none
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  # check-runs Phase 2 (trigger guard) and Phase 3 poll: conclusion=success.
  # Output one page as a raw JSON object (no outer array) to match gh --paginate
  # format: each page is a top-level object with a check_runs key.
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"success","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  # headRefOid refresh inside poll loop
  *"headRefOid"*)
    printf 'abc161sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_161
chmod +x "$_bugbot_mock_dir_161/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_161:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_clean_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_clean_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "bugbot_clean_exit_code" "0" "$actual_exit"
rm -rf "$_bugbot_mock_dir_161"
unset _bugbot_mock_dir_161 actual_output actual_exit

# A successful check-run with both an explicit skip and a real finding must
# preserve the blocker. The comments endpoint returns empty for Phase 1, then
# mixed comments for the success-conclusion inspection.
_bugbot_mock_dir_161b="$(mktemp -d)"
printf '0\n' > "$_bugbot_mock_dir_161b/comment_calls"
cat > "$_bugbot_mock_dir_161b/gh" <<'BUGBOT_GH_161B'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc161bsha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -eq 1 ]; then
      printf '[]\n'
    else
      printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","commit_id":"abc161bsha","path":"src/lib.c","line":10,"body":"Skipping Bugbot: your auto mode classified this PR to skip. Visit the Bugbot dashboard to update your settings."},{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:01:00Z","commit_id":"abc161bsha","path":"src/lib.c","line":11,"body":"BUGBOT_REVIEW: null pointer"}]\n'
    fi
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"success","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc161bsha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_161B
chmod +x "$_bugbot_mock_dir_161b/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_161b:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_success_blocker_beats_explicit_skip_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_success_blocker_beats_explicit_skip_blocking_count" "BLOCKING_COUNT=1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "bugbot_success_blocker_beats_explicit_skip_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_161b"
unset _bugbot_mock_dir_161b actual_output actual_exit

# A blocking check conclusion with only an explicit skip message should still
# surface the authoritative skip, not a synthetic blocker.
_bugbot_mock_dir_161c="$(mktemp -d)"
printf '0\n' > "$_bugbot_mock_dir_161c/comment_calls"
cat > "$_bugbot_mock_dir_161c/gh" <<'BUGBOT_GH_161C'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc161csha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -eq 1 ]; then
      printf '[]\n'
    else
      printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","commit_id":"abc161csha","path":"src/lib.c","line":10,"body":"Skipping Bugbot: your auto mode classified this PR to skip. Visit the Bugbot dashboard to update your settings."}]\n'
    fi
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"failure","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc161csha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_161C
chmod +x "$_bugbot_mock_dir_161c/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_161c:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_failure_explicit_skip_only_result" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_failure_explicit_skip_only_reason" "REASON=explicit-skip" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_failure_explicit_skip_only_exit_code" "0" "$actual_exit"
rm -rf "$_bugbot_mock_dir_161c"
unset _bugbot_mock_dir_161c actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.2: needs_fixes path — conclusion=failure, blocking cursor[bot] review
# ---------------------------------------------------------------------------
_bugbot_mock_dir_162="$(mktemp -d)"
cat > "$_bugbot_mock_dir_162/gh" <<'BUGBOT_GH_162'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc162sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  # Phase 1 existing comments — none on entry
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  # Phase 1 existing reviews — none on entry; Phase 3 blocking review
  *"pulls/"*"/reviews"*)
    printf '[{"user":{"login":"cursor[bot]"},"submitted_at":"2020-01-02T00:00:00Z","state":"CHANGES_REQUESTED","body":"BUGBOT_REVIEW: null pointer dereference at src/main.c:42"}]\n'
    exit 0 ;;
  # Output raw page object (no outer array) to match gh --paginate format.
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"failure","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc162sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_162
chmod +x "$_bugbot_mock_dir_162/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_162:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_needs_fixes_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_needs_fixes_blocking_count_nonzero" "1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=" | cut -d= -f2)"
run_test "bugbot_needs_fixes_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_162"
unset _bugbot_mock_dir_162 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.2b: CHANGES_REQUESTED review blocks even with clean body text
# ---------------------------------------------------------------------------
_bugbot_mock_dir_162b="$(mktemp -d)"
cat > "$_bugbot_mock_dir_162b/gh" <<'BUGBOT_GH_162B'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc162bsha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    printf 'ERROR: trigger POST reached unexpectedly\n' >&2; exit 1 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"user":{"login":"cursor[bot]"},"submitted_at":"2020-01-02T00:00:00Z","commit_id":"abc162bsha","state":"CHANGES_REQUESTED","body":"Cursor Bugbot found no issues in this pull request."}]\n'
    exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"success","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc162bsha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_162B
chmod +x "$_bugbot_mock_dir_162b/gh"

actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_162b:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_changes_requested_clean_body_blocks_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_changes_requested_clean_body_blocks_count" "1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=" | cut -d= -f2)"
run_test "bugbot_changes_requested_clean_body_blocks_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_162b"
unset _bugbot_mock_dir_162b actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.2c: CHANGES_REQUESTED review blocks even with an empty body
# ---------------------------------------------------------------------------
_bugbot_mock_dir_162c="$(mktemp -d)"
cat > "$_bugbot_mock_dir_162c/gh" <<'BUGBOT_GH_162C'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc162csha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"user":{"login":"cursor[bot]"},"submitted_at":"2020-01-02T00:00:00Z","commit_id":"abc162csha","state":"CHANGES_REQUESTED","body":""}]\n'
    exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"success","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc162csha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_162C
chmod +x "$_bugbot_mock_dir_162c/gh"

actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_162c:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_changes_requested_empty_body_blocks_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_changes_requested_empty_body_blocks_count" "1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=" | cut -d= -f2)"
run_test "bugbot_changes_requested_empty_body_blocks_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_162c"
unset _bugbot_mock_dir_162c actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.3: escalate (timeout) — run appeared but never completed
# poll_interval=1, max_wait=2: loop runs once (sets check_appeared=1 via
# in_progress status), then budget exhausted → REASON=timeout
# ---------------------------------------------------------------------------
_bugbot_mock_dir_163="$(mktemp -d)"
cat > "$_bugbot_mock_dir_163/gh" <<'BUGBOT_GH_163'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc163sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  # Return in_progress (raw page object) so check_appeared is set but run never completes.
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"in_progress","conclusion":null,"started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc163sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_163
chmod +x "$_bugbot_mock_dir_163/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_163:$PATH" run_bugbot_review "42" "feature/42-test" "1" "1" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_timeout_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_timeout_reason" "REASON=timeout" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_timeout_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_163"
unset _bugbot_mock_dir_163 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.4: escalate (unavailable) — no check run appeared within budget
# max_wait=0: poll loop never executes, check_appeared=0 → REASON=unavailable
# ---------------------------------------------------------------------------
_bugbot_mock_dir_164="$(mktemp -d)"
cat > "$_bugbot_mock_dir_164/gh" <<'BUGBOT_GH_164'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc164sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  # check-runs: no Cursor Bugbot runs → triggers POST (handled above), then
  # poll loop doesn't run because max_wait=0 → check_appeared stays 0.
  # Output raw page object (no outer array) to match gh --paginate format.
  *"check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_164
chmod +x "$_bugbot_mock_dir_164/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_164:$PATH" run_bugbot_review "42" "feature/42-test" "1" "0" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_unavailable_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_unavailable_reason" "REASON=unavailable" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_unavailable_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_164"
unset _bugbot_mock_dir_164 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.4b: explicit Bugbot skip issue comment is warning-only
#
# Cursor can post an issue comment saying Bugbot skipped the PR before a check
# run appears. That is an explicit platform decision, not an unavailable
# reviewer; the loop must surface it as RESULT=skipped and avoid trigger POST.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_164b="$(mktemp -d)"
cat > "$_bugbot_mock_dir_164b/gh" <<'BUGBOT_GH_164B'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc164bsha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","body":"Skipping Bugbot: your auto mode classified this PR to skip. Visit the Bugbot dashboard to update your settings."}]\n'
    exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  *)
    printf 'ERROR: unexpected gh call: %s\n' "$*" >&2; exit 1 ;;
esac
BUGBOT_GH_164B
chmod +x "$_bugbot_mock_dir_164b/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_164b:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_explicit_skip_result" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_explicit_skip_reason" "REASON=explicit-skip" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_explicit_skip_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "bugbot_explicit_skip_exit_code" "0" "$actual_exit"
rm -rf "$_bugbot_mock_dir_164b"
unset _bugbot_mock_dir_164b actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.5: escalate (head-sha-unavailable) — pulls API returns empty SHA
# ---------------------------------------------------------------------------
_bugbot_mock_dir_165="$(mktemp -d)"
cat > "$_bugbot_mock_dir_165/gh" <<'BUGBOT_GH_165'
#!/usr/bin/env bash
case "$*" in
  # pulls API returns empty body — jq produces empty string
  *"--jq .head.sha"*)
    printf '\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_165
chmod +x "$_bugbot_mock_dir_165/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_165:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_head_sha_unavailable_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_head_sha_unavailable_reason" "REASON=head-sha-unavailable" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_head_sha_unavailable_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_165"
unset _bugbot_mock_dir_165 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.6: idempotency fast-path — existing blocking cursor[bot] finding on HEAD
#
# When blocking cursor[bot] inline or review comments already exist for the
# current HEAD, run_bugbot_review must return needs_fixes with
# REASON=existing_findings immediately (Phase 1), without posting a trigger
# comment.  The mock returns an existing CHANGES_REQUESTED review from
# cursor[bot]; the check-runs and trigger POST endpoints must NOT be reached
# (they return non-zero to confirm they were not invoked).
# ---------------------------------------------------------------------------
_bugbot_mock_dir_166="$(mktemp -d)"
cat > "$_bugbot_mock_dir_166/gh" <<'BUGBOT_GH_166'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc166sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  # Phase 1 inline comments — none
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  # Phase 1 reviews — one blocking CHANGES_REQUESTED from cursor[bot]
  *"pulls/"*"/reviews"*)
    printf '[{"user":{"login":"cursor[bot]"},"submitted_at":"2020-01-02T00:00:00Z","commit_id":"abc166sha","state":"CHANGES_REQUESTED","body":"BUGBOT_REVIEW: null pointer at src/lib.c:10"}]\n'
    exit 0 ;;
  # check-runs and trigger POST must NOT be reached (function returns early)
  *"check-runs"*)
    printf 'ERROR: check-runs reached unexpectedly\n' >&2; exit 1 ;;
  *"--method POST"*)
    printf 'ERROR: trigger POST reached unexpectedly\n' >&2; exit 1 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_166
chmod +x "$_bugbot_mock_dir_166/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_166:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_existing_findings_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_existing_findings_reason" "REASON=existing_findings" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_existing_findings_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_166"
unset _bugbot_mock_dir_166 actual_output actual_exit

# Existing blockers must take precedence over an explicit skip comment.
_bugbot_mock_dir_166b="$(mktemp -d)"
cat > "$_bugbot_mock_dir_166b/gh" <<'BUGBOT_GH_166B'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc166bsha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","commit_id":"abc166bsha","path":"src/lib.c","line":10,"body":"BUGBOT_REVIEW: null pointer"},{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:01:00Z","commit_id":"abc166bsha","path":"src/lib.c","line":11,"body":"Skipping Bugbot: your auto mode classified this PR to skip. Visit the Bugbot dashboard to update your settings."}]\n'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf 'ERROR: check-runs reached unexpectedly\n' >&2; exit 1 ;;
  *"--method POST"*)
    printf 'ERROR: trigger POST reached unexpectedly\n' >&2; exit 1 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_166B
chmod +x "$_bugbot_mock_dir_166b/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_166b:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_existing_blocker_beats_explicit_skip_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_existing_blocker_beats_explicit_skip_blocking_count" "BLOCKING_COUNT=1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "bugbot_existing_blocker_beats_explicit_skip_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_166b"
unset _bugbot_mock_dir_166b actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.7: trigger-failed path — trigger comment POST fails
#
# When no check run exists for the head SHA (Phase 2 count=0), the function
# posts a trigger comment.  If that POST fails, the function must escalate
# with REASON=trigger-failed.  The mock returns an empty check-runs page so
# the trigger POST branch is reached, then returns non-zero for the POST.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_167="$(mktemp -d)"
cat > "$_bugbot_mock_dir_167/gh" <<'BUGBOT_GH_167'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc167sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  # Phase 2: no Bugbot run → trigger POST will be attempted
  *"check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  # Trigger comment POST fails
  *"--method POST"*)
    exit 1 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_167
chmod +x "$_bugbot_mock_dir_167/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_167:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_trigger_failed_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_trigger_failed_reason" "REASON=trigger-failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_trigger_failed_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_167"
unset _bugbot_mock_dir_167 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.8: fetch-failed path — check-run API call fails during Phase 3 poll
#
# After a successful trigger, the poll loop calls the check-runs API each
# iteration.  When that call fails, the function must escalate immediately
# with REASON=fetch-failed rather than continuing to loop or returning clean.
#
# The mock differentiates Phase 2 (first check-runs call; returns empty so
# the trigger fires) from Phase 3 poll (second check-runs call; returns
# non-zero exit) using a call counter written to a tmp file.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_168="$(mktemp -d)"
_bugbot_cr_counter_168="/tmp/bugbot-test-168-cr-count.$$"
rm -f "$_bugbot_cr_counter_168"
cat > "$_bugbot_mock_dir_168/gh" <<BUGBOT_GH_168
#!/usr/bin/env bash
_counter_file="${_bugbot_cr_counter_168}"
case "\$*" in
  *"--jq .head.sha"*)
    printf 'abc168sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    _n="\$(cat "\$_counter_file" 2>/dev/null || printf '0')"
    _n=\$(( _n + 1 ))
    printf '%s\n' "\$_n" > "\$_counter_file"
    if [ "\$_n" -eq 1 ]; then
      # Phase 2: return empty page so trigger POST is attempted
      printf '{"check_runs":[]}\n'; exit 0
    else
      # Phase 3 poll: fail to trigger fetch-failed branch
      exit 1
    fi ;;
  *"--method POST"*)
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc168sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_168
chmod +x "$_bugbot_mock_dir_168/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_168:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_fetch_failed_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_fetch_failed_reason" "REASON=fetch-failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_fetch_failed_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_168"
rm -f "$_bugbot_cr_counter_168"
unset _bugbot_mock_dir_168 _bugbot_cr_counter_168 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.8b: fetch-failed path — Phase 2 check-run API call fails before trigger
#
# A failed check-run read must not be treated as "zero check runs" and must not
# trigger a Bugbot comment. It escalates as fetch-failed immediately.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_168b="$(mktemp -d)"
cat > "$_bugbot_mock_dir_168b/gh" <<'BUGBOT_GH_168B'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc168bsha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    exit 1 ;;
  *"--method POST"*)
    printf 'ERROR: trigger POST reached unexpectedly\n' >&2; exit 1 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_168B
chmod +x "$_bugbot_mock_dir_168b/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_168b:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_phase2_fetch_failed_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_phase2_fetch_failed_reason" "REASON=fetch-failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_phase2_fetch_failed_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_168b"
unset _bugbot_mock_dir_168b actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.8c: fetch-failed path — Phase 2 check-run JSON parse fails
#
# Malformed check-run JSON must also escalate as fetch-failed instead of being
# coerced to an empty run list.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_168c="$(mktemp -d)"
cat > "$_bugbot_mock_dir_168c/gh" <<'BUGBOT_GH_168C'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc168csha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{not-json\n'; exit 0 ;;
  *"--method POST"*)
    printf 'ERROR: trigger POST reached unexpectedly\n' >&2; exit 1 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_168C
chmod +x "$_bugbot_mock_dir_168c/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_168c:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_phase2_parse_failed_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_phase2_parse_failed_reason" "REASON=fetch-failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_phase2_parse_failed_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_168c"
unset _bugbot_mock_dir_168c actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.9: neutral conclusion path — check run concludes neutral
#
# A neutral conclusion (e.g. skipped analysis) is informational and must be
# treated as clean with zero blocking findings and zero suggestions, matching
# the neutral|cancelled|skipped branch in run_bugbot_review.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_169="$(mktemp -d)"
cat > "$_bugbot_mock_dir_169/gh" <<'BUGBOT_GH_169'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc169sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  # check-runs: completed with conclusion=neutral
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"neutral","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc169sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_169
chmod +x "$_bugbot_mock_dir_169/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_169:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_neutral_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_neutral_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "bugbot_neutral_suggestion_count" "SUGGESTION_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^SUGGESTION_COUNT=")"
run_test "bugbot_neutral_exit_code" "0" "$actual_exit"
rm -rf "$_bugbot_mock_dir_169"
unset _bugbot_mock_dir_169 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.9.1: neutral usage-limit comment escalates
#
# Cursor can conclude the check run as neutral while posting an issue comment
# that Bugbot could not run because a usage/spend limit was reached. That is
# unavailable, not clean.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_1691="$(mktemp -d)"
cat > "$_bugbot_mock_dir_1691/gh" <<'BUGBOT_GH_1691'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1691sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-01T00:00:01Z","body":"Bugbot could not run - usage limit reached. The organization hit a usage or spend limit."}]\n'
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"neutral","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc1691sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_1691
chmod +x "$_bugbot_mock_dir_1691/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_1691:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_neutral_usage_limit_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_neutral_usage_limit_reason" "REASON=bugbot-usage-limit" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_neutral_usage_limit_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_1691"
unset _bugbot_mock_dir_1691 actual_output actual_exit

# Test 16.9.2: neutral usage-limit comment from prior head is ignored
_bugbot_mock_dir_1692="$(mktemp -d)"
cat > "$_bugbot_mock_dir_1692/gh" <<'BUGBOT_GH_1692'
#!/usr/bin/env bash
case "$*" in
  *"commits/abc1692old"*".commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1692new"*".commit.committer.date"*)
    printf '2020-01-03T00:00:00Z\n'; exit 0 ;;
  *"--jq .head.sha"*)
    printf 'abc1692old\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","body":"Bugbot could not run - usage limit reached."}]\n'
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"neutral","started_at":"2020-01-01T00:00:01Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc1692new\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_1692
chmod +x "$_bugbot_mock_dir_1692/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_1692:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_neutral_stale_usage_limit_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_neutral_stale_usage_limit_exit_code" "0" "$actual_exit"
rm -rf "$_bugbot_mock_dir_1692"
unset _bugbot_mock_dir_1692 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.10: run_platform_review routes "bugbot" to run_bugbot_review
# ---------------------------------------------------------------------------
_bugbot_dispatch_called=0
run_bugbot_review() { _bugbot_dispatch_called=1; }
run_platform_review "bugbot" "999" "feature/test" "30" "120" >/dev/null 2>&1 || true
run_test "run_platform_review_routes_to_run_bugbot_review" "1" "$_bugbot_dispatch_called"
unset -f run_bugbot_review
unset _bugbot_dispatch_called
HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
workflow_repo_root() { printf '%s\n' "${HARNESS_REPO_ROOT:-$REPO_ROOT}"; }

# ---------------------------------------------------------------------------
# Test 16.11: disabled Bugbot preflight — escalate with bugbot-disabled
# ---------------------------------------------------------------------------
_bugbot_mock_dir_1611="$(mktemp -d)"
cat > "$_bugbot_mock_dir_1611/gh" <<'BUGBOT_GH_1611'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1611sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","body":"Bugbot is disabled for this repository."}]\n'
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_1611
chmod +x "$_bugbot_mock_dir_1611/gh"

actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  PATH="$_bugbot_mock_dir_1611:$PATH"
  _ec=0
  run_bugbot_review "42" "feature/42-test" "1" "30" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_disabled_preflight_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_disabled_preflight_reason" "REASON=bugbot-disabled" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_disabled_preflight_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_1611"
unset _bugbot_mock_dir_1611 actual_output actual_exit

# Test 16.12: stale disabled issue comment before HEAD is ignored
_bugbot_mock_dir_1612="$(mktemp -d)"
cat > "$_bugbot_mock_dir_1612/gh" <<'BUGBOT_GH_1612'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1612sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-02T00:00:00Z\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-01T00:00:00Z","body":"Bugbot is disabled for this repository."}]\n'
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"success","started_at":"2020-01-02T00:00:00Z"}]}\n'
    exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_1612
chmod +x "$_bugbot_mock_dir_1612/gh"

actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  PATH="$_bugbot_mock_dir_1612:$PATH"
  _ec=0
  run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_stale_disabled_comment_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_stale_disabled_comment_exit_code" "0" "$actual_exit"
rm -rf "$_bugbot_mock_dir_1612"
unset _bugbot_mock_dir_1612 actual_output actual_exit

# ---------------------------------------------------------------------------
# Area 17: PR-Agent explicit trigger model
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 17: PR-Agent explicit trigger model ==="

_pr_agent_mock_dir_1701="$(mktemp -d)"
_pr_agent_call_log_1701="$_pr_agent_mock_dir_1701/calls.log"
cat > "$_pr_agent_mock_dir_1701/gh" <<'PR_AGENT_GH_1701'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PR_AGENT_CALL_LOG"
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1701sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"-X POST"*"issues/42/comments"*)
    printf '{"created_at":"2020-01-01T00:00:01Z"}\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
PR_AGENT_GH_1701
chmod +x "$_pr_agent_mock_dir_1701/gh"

actual_output="$(
  PATH="$_pr_agent_mock_dir_1701:$PATH" PR_AGENT_CALL_LOG="$_pr_agent_call_log_1701" \
    run_pr_agent_review "42" "feature/42-test" "1" "0" || true
)"
run_test "pr_agent_posts_explicit_trigger" "PR_AGENT_TRIGGER_COMMENT=/review" \
  "$(printf '%s\n' "$actual_output" | grep "^PR_AGENT_TRIGGER_COMMENT=")"
run_test "pr_agent_no_review_after_trigger_skips" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "pr_agent_trigger_post_call_made" "1" \
  "$(grep_count_or_zero "-X POST repos/.*/issues/42/comments" "$_pr_agent_call_log_1701")"
rm -rf "$_pr_agent_mock_dir_1701"
unset _pr_agent_mock_dir_1701 _pr_agent_call_log_1701 actual_output

_pr_agent_mock_dir_1702="$(mktemp -d)"
_pr_agent_call_log_1702="$_pr_agent_mock_dir_1702/calls.log"
cat > "$_pr_agent_mock_dir_1702/gh" <<'PR_AGENT_GH_1702'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PR_AGENT_CALL_LOG"
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1702sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '[{"user":{"login":"github-actions[bot]"},"updated_at":"2020-01-01T00:00:02Z","html_url":"https://example.test/comment","body":"PR Reviewer Guide abc1702sha\\nNo major issues detected"}]\n'
    exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
PR_AGENT_GH_1702
chmod +x "$_pr_agent_mock_dir_1702/gh"

actual_output="$(
  PATH="$_pr_agent_mock_dir_1702:$PATH" PR_AGENT_CALL_LOG="$_pr_agent_call_log_1702" \
    run_pr_agent_review "42" "feature/42-test" "1" "0" || true
)"
run_test "pr_agent_reuses_existing_comment" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "pr_agent_existing_comment_no_duplicate_trigger" "0" \
  "$(grep_count_or_zero "-X POST repos/.*/issues/42/comments" "$_pr_agent_call_log_1702")"
rm -rf "$_pr_agent_mock_dir_1702"
unset _pr_agent_mock_dir_1702 _pr_agent_call_log_1702 actual_output

_pr_agent_mock_dir_1703="$(mktemp -d)"
_pr_agent_call_log_1703="$_pr_agent_mock_dir_1703/calls.log"
cat > "$_pr_agent_mock_dir_1703/gh" <<'PR_AGENT_GH_1703'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PR_AGENT_CALL_LOG"
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1703sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1703sha/check-runs"*)
    printf '{"check_runs":[]}\n{"check_runs":[{"name":"PR-Agent review","status":"in_progress"}]}\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
PR_AGENT_GH_1703
chmod +x "$_pr_agent_mock_dir_1703/gh"

actual_output="$(
  PATH="$_pr_agent_mock_dir_1703:$PATH" PR_AGENT_CALL_LOG="$_pr_agent_call_log_1703" \
    run_pr_agent_review "42" "feature/42-test" "1" "0" || true
)"
run_test "pr_agent_active_check_no_duplicate_trigger" "PR_AGENT_TRIGGER_SKIPPED=active_review_in_progress" \
  "$(printf '%s\n' "$actual_output" | grep "^PR_AGENT_TRIGGER_SKIPPED=")"
run_test "pr_agent_active_check_waits_then_skips" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "pr_agent_active_check_no_post_call" "0" \
  "$(grep_count_or_zero "-X POST repos/.*/issues/42/comments" "$_pr_agent_call_log_1703")"
rm -rf "$_pr_agent_mock_dir_1703"
unset _pr_agent_mock_dir_1703 _pr_agent_call_log_1703 actual_output

_pr_agent_mock_dir_1704="$(mktemp -d)"
_pr_agent_call_log_1704="$_pr_agent_mock_dir_1704/calls.log"
cat > "$_pr_agent_mock_dir_1704/gh" <<'PR_AGENT_GH_1704'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PR_AGENT_CALL_LOG"
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1704sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1704sha/check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '[{"user":{"login":"lhpaul"},"created_at":"2020-01-01T00:00:01Z","updated_at":"2020-01-01T00:00:01Z","body":"/review"}]\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
PR_AGENT_GH_1704
chmod +x "$_pr_agent_mock_dir_1704/gh"

actual_output="$(
  PATH="$_pr_agent_mock_dir_1704:$PATH" PR_AGENT_CALL_LOG="$_pr_agent_call_log_1704" \
    PR_AGENT_TRIGGER_REUSE_WINDOW_SECONDS=999999999 \
    run_pr_agent_review "42" "feature/42-test" "1" "0" || true
)"
run_test "pr_agent_recent_trigger_no_duplicate_trigger" "PR_AGENT_TRIGGER_SKIPPED=recent_review_trigger" \
  "$(printf '%s\n' "$actual_output" | grep "^PR_AGENT_TRIGGER_SKIPPED=")"
run_test "pr_agent_recent_trigger_waits_then_skips" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "pr_agent_recent_trigger_no_post_call" "0" \
  "$(grep_count_or_zero "-X POST repos/.*/issues/42/comments" "$_pr_agent_call_log_1704")"
rm -rf "$_pr_agent_mock_dir_1704"
unset _pr_agent_mock_dir_1704 _pr_agent_call_log_1704 actual_output

_pr_agent_mock_dir_1705="$(mktemp -d)"
_pr_agent_call_log_1705="$_pr_agent_mock_dir_1705/calls.log"
cat > "$_pr_agent_mock_dir_1705/gh" <<'PR_AGENT_GH_1705'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PR_AGENT_CALL_LOG"
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1705sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1705sha/check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  *"-X POST"*"issues/42/comments"*)
    printf '{"created_at":"2026-06-30T00:00:00Z"}\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '[{"user":{"login":"lhpaul"},"created_at":"2020-01-01T00:00:01Z","updated_at":"2020-01-01T00:00:01Z","body":"/review"}]\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
PR_AGENT_GH_1705
chmod +x "$_pr_agent_mock_dir_1705/gh"

actual_output="$(
  PATH="$_pr_agent_mock_dir_1705:$PATH" PR_AGENT_CALL_LOG="$_pr_agent_call_log_1705" \
    PR_AGENT_TRIGGER_REUSE_WINDOW_SECONDS=1 \
    run_pr_agent_review "42" "feature/42-test" "1" "0" || true
)"
run_test "pr_agent_stale_trigger_posts_new_trigger" "PR_AGENT_TRIGGER_COMMENT=/review" \
  "$(printf '%s\n' "$actual_output" | grep "^PR_AGENT_TRIGGER_COMMENT=")"
run_test "pr_agent_stale_trigger_post_call_made" "1" \
  "$(grep_count_or_zero "-X POST repos/.*/issues/42/comments" "$_pr_agent_call_log_1705")"
rm -rf "$_pr_agent_mock_dir_1705"
unset _pr_agent_mock_dir_1705 _pr_agent_call_log_1705 actual_output

_pr_agent_mock_dir_1706="$(mktemp -d)"
cat > "$_pr_agent_mock_dir_1706/gh" <<'PR_AGENT_GH_1706'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1706sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1706sha/check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  *"-X POST"*"issues/42/comments"*)
    exit 1 ;;
  *"issues/42/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
PR_AGENT_GH_1706
chmod +x "$_pr_agent_mock_dir_1706/gh"

actual_output="$(
  PATH="$_pr_agent_mock_dir_1706:$PATH" run_pr_agent_review "42" "feature/42-test" "1" "0" || true
)"
run_test "pr_agent_trigger_failure_escalates" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "pr_agent_trigger_failure_reason" "REASON=pr_agent_trigger_failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
rm -rf "$_pr_agent_mock_dir_1706"
unset _pr_agent_mock_dir_1706 actual_output

run_test "pr_agent_workflow_synchronize_trigger" "1" \
  "$(grep_count_or_zero "types:.*synchronize" "$REPO_ROOT/.github/workflows/pr-agent.yml")"
run_test "pr_agent_workflow_exact_review_command" "1" \
  "$(grep_count_or_zero "github.event.comment.body == '/review'" "$REPO_ROOT/.github/workflows/pr-agent.yml")"

# ---------------------------------------------------------------------------
# Area: coderabbit_success_status_count (issue #1437)
#
# Verifies the shared helper used by both coderabbit_status_success_fallback
# call sites in run_coderabbit_review rejects a `success` commit status whose
# description indicates the review was rate-limited / did not actually run,
# while still counting a genuine success status as clean evidence. Uses the
# same MOCK_GH_OUTPUT single-array pattern as Area 2 (check_unreplied_rest_comments):
# --paginate | jq -s flattens via .[].[] so a single JSON array is sufficient.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area: coderabbit_success_status_count (issue #1437) ==="

unset MOCK_GH_POST_EXIT MOCK_GH_POST_OUTPUT MOCK_GH_CALL_LOG MOCK_GH_EXIT

# CONTROL: genuine success status with a normal description — must count as 1.
# This is the "still reports clean for a genuine success description" direction.
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"Review completed: 0 findings","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_genuine_success" "1" "$actual"

# PLANTED VIOLATION: success status whose description is CodeRabbit's confirmed
# rate-limit banner text — must NOT count (0), proving the false-clean hole from
# issue #1437 is closed. Before this fix, checking .state alone would have
# returned 1 here (false clean).
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"Review limit reached. Next review available in: 43 minutes","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_rate_limited_description_rejected" "0" "$actual"

# Rate-limit description with different casing and hyphen separator — regex is
# the same test("rate.?limit"; "i") pattern already used elsewhere in this script.
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"RATE-LIMIT: try again later","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_rate_limit_hyphen_case_insensitive" "0" "$actual"

# Each alternative in the "rate.?limit|review limit|next review available"
# regex must independently reject on its own — tested in isolation so a future
# accidental removal of one alternative is caught even if the other two still
# pass. "review limit" alone (no "rate limit" or "next review available" text).
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"Review limit exceeded for this repository","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_review_limit_phrase_alone_rejected" "0" "$actual"

# "next review available" alone (no "rate limit" or "review limit" text).
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"Please retry — next review available shortly","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_next_review_available_phrase_alone_rejected" "0" "$actual"

# Non-success state is never counted regardless of description.
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"pending","description":"Reviewing...","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_pending_not_counted" "0" "$actual"

# Missing/null description on a genuine success status must still count (no
# regression for the common case where CodeRabbit sets no description at all).
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_missing_description_still_counts" "1" "$actual"

# Dedup by context: an older genuine success is superseded by a newer
# rate-limited success on the same context — only the latest (rejected) entry
# should be considered, so the count must be 0.
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"Review completed: 0 findings","updated_at":"2026-08-10T00:00:00Z"},{"context":"coderabbit/review","state":"success","description":"Review limit reached. Next review available in: 10 minutes","updated_at":"2026-08-10T00:05:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_dedup_latest_rate_limited" "0" "$actual"

# Dedup by context: an older rate-limited success is superseded by a newer
# genuine success on the same context — the count must be 1.
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"Review limit reached. Next review available in: 10 minutes","updated_at":"2026-08-10T00:00:00Z"},{"context":"coderabbit/review","state":"success","description":"Review completed: 0 findings","updated_at":"2026-08-10T00:05:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_dedup_latest_genuine" "1" "$actual"

# Non-coderabbit context is ignored entirely.
export MOCK_GH_OUTPUT='[{"context":"ci/build","state":"success","description":"rate limit exceeded","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_non_coderabbit_context_ignored" "0" "$actual"

# Argument validation: empty repo or head_sha must short-circuit before the
# `gh api` call (asserted via MOCK_GH_CALL_LOG — the mock's default fallback
# returns "[]"/exit 0 for ANY input, so checking only the return value/exit
# code would pass even without the guard; the call-log assertion is what
# actually proves the guard prevents the API call) and must safely return "0"
# rather than propagating a nonzero exit status, since both call sites assign
# this function's output via `var="$(coderabbit_success_status_count ...)"`
# under `set -euo pipefail`, where a nonzero return would abort the whole
# reviewer-loop script instead of falling through to the normal "no success
# status found" path.
unset MOCK_GH_OUTPUT
_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log"
actual="$(coderabbit_success_status_count "" "abc123")"
actual_exit=$?
run_test "coderabbit_success_status_count_empty_repo_returns_zero" "0" "$actual"
run_test "coderabbit_success_status_count_empty_repo_exit_zero" "0" "$actual_exit"
run_test "coderabbit_success_status_count_empty_repo_no_api_call" "" "$(cat "$_call_log")"
rm -f "$_call_log"
unset MOCK_GH_CALL_LOG

_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log"
actual="$(coderabbit_success_status_count "owner/repo" "")"
actual_exit=$?
run_test "coderabbit_success_status_count_empty_head_sha_returns_zero" "0" "$actual"
run_test "coderabbit_success_status_count_empty_head_sha_exit_zero" "0" "$actual_exit"
run_test "coderabbit_success_status_count_empty_head_sha_no_api_call" "" "$(cat "$_call_log")"
rm -f "$_call_log"
unset MOCK_GH_CALL_LOG

# ---------------------------------------------------------------------------
# Area: coderabbit_no_trigger_timeout_default (issue #1433)
#
# Verifies the computed default for the CodeRabbit silent-non-trigger fallback
# timeout (scripts/development-workflow/pr-review-loop.sh lines 3989-4004).
# Prior behavior: a fixed 600 s default, decoupled from --max-wait. Two bugs
# this fixes: (1) latency — 600 s of pure idle wait before the proactive
# "@coderabbitai review" nudge on the common default max_wait=1200 invocation;
# (2) correctness — on short-max_wait invocations (e.g. the 180 s doc-branch
# default) elapsed could never reach 600 before the outer max_wait exit, so
# the silent-non-trigger safety net could never fire at all.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area: coderabbit_no_trigger_timeout_default (issue #1433) ==="

# CONTROL / latency fix: the common default invocation (max_wait=1200, the
# hardcoded default in main()) must now yield 180 — a 420 s (7 min) reduction
# from the old fixed 600 s default. half_max_wait=600 does not cap the 180 s
# hardcoded default, so the hardcoded value wins.
actual="$(coderabbit_no_trigger_timeout_default 1200)"
run_test "no_trigger_timeout_default_common_max_wait_1200" "180" "$actual"

# PLANTED VIOLATION / correctness fix: doc-branch default max_wait=180. Under
# the OLD fixed-600 default, elapsed could never reach 600 before the loop's
# own "elapsed >= max_wait" (180) exit fires first — the silent-non-trigger
# retrigger block (pr-review-loop.sh ~line 4315,
# `coderabbit_no_trigger_retriggers < ... && elapsed >= coderabbit_no_trigger_timeout`)
# would be permanently unreachable on these branches. The half-max_wait cap
# (line 3996) must produce 90 (half of 180, below the 180 hardcoded default)
# so the fallback has room to fire with a full max_wait/2 remaining for a
# subsequent poll cycle. Reverting the cap (deleting lines 3994-3999, leaving
# only the hardcoded 180 default) makes this assertion fail — 180 is not < 180
# under `--max-wait 180`, so the retrigger could never fire before timeout;
# this was manually verified during implementation (see PR description) and
# is the concrete regression this test guards against.
actual="$(coderabbit_no_trigger_timeout_default 180)"
run_test "no_trigger_timeout_default_doc_branch_max_wait_180_capped" "90" "$actual"

# Large-diff invocation (max_wait=2400): half is 1200, well above the 180
# hardcoded default, so the cap must NOT kick in — the hardcoded default wins.
actual="$(coderabbit_no_trigger_timeout_default 2400)"
run_test "no_trigger_timeout_default_large_diff_max_wait_2400_uncapped" "180" "$actual"

# Floor: a pathologically small max_wait (40) yields half_max_wait=20, below
# the 30 s floor (line 4000-4002) — the floor must win over the smaller capped
# value so at least one nudge attempt has a usable window.
actual="$(coderabbit_no_trigger_timeout_default 40)"
run_test "no_trigger_timeout_default_floor_applies_below_30" "30" "$actual"

# Boundary: max_wait=360 -> half=180, exactly equal to the hardcoded default.
# The cap only applies when half_max_wait is STRICTLY less than the hardcoded
# default (line 3996 uses `-lt`), so at the boundary the hardcoded default
# must still be the result (not fall through to some other branch).
actual="$(coderabbit_no_trigger_timeout_default 360)"
run_test "no_trigger_timeout_default_boundary_max_wait_360" "180" "$actual"

# Invalid/empty max_wait must safely fall back to the hardcoded default
# instead of crashing on arithmetic with a non-numeric value.
actual="$(coderabbit_no_trigger_timeout_default "")"
run_test "no_trigger_timeout_default_empty_max_wait_fallback" "180" "$actual"

actual="$(coderabbit_no_trigger_timeout_default "not-a-number")"
run_test "no_trigger_timeout_default_non_numeric_max_wait_fallback" "180" "$actual"

# Zero max_wait must not attempt a division-relevant cap and must fall back to
# the hardcoded default (guarded by `-gt 0` on line 3994).
actual="$(coderabbit_no_trigger_timeout_default 0)"
run_test "no_trigger_timeout_default_zero_max_wait_fallback" "180" "$actual"

# Leading-zero decimal input (CodeRabbit finding on PR #1458): "080" passes
# the ^[0-9]+$ digit-only regex guard but, without base-10 normalization, bash
# arithmetic expansion parses a leading-zero literal as octal — and "080" is
# not a valid octal literal (8 is not an octal digit), so `$((080 / 2))`
# errors with "value too great for base" and aborts the script under
# `set -euo pipefail`. The `10#$max_wait` prefix forces base-10 interpretation
# so this must safely compute 40 (half of 80) instead of erroring.
actual="$(coderabbit_no_trigger_timeout_default 080)"
run_test "no_trigger_timeout_default_leading_zero_max_wait_normalized_base10" "40" "$actual"

# ---------------------------------------------------------------------------
# Area: coderabbit_resolve_no_trigger_timeout (issue #1433, CodeRabbit finding
# on PR #1458) — exercises the actual production override-resolution path
# used by run_coderabbit_review, not just the underlying default-computation
# helper tested above.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area: coderabbit_resolve_no_trigger_timeout (issue #1433) ==="

# No override set: must fall through to coderabbit_no_trigger_timeout_default.
unset CODERABBIT_NO_TRIGGER_TIMEOUT
actual="$(coderabbit_resolve_no_trigger_timeout 180)"
run_test "no_trigger_resolve_no_override_uses_computed_default" "90" "$actual"

# An explicit override larger than the computed default for the given
# max_wait must be honored as-is (uncapped) rather than silently reduced —
# same pattern already used by CODERABBIT_RATE_LIMIT_WAIT / _MAX_RETRIES.
export CODERABBIT_NO_TRIGGER_TIMEOUT=900
actual="$(coderabbit_resolve_no_trigger_timeout 180)"
run_test "no_trigger_resolve_explicit_override_honored_uncapped" "900" "$actual"
unset CODERABBIT_NO_TRIGGER_TIMEOUT

# An invalid explicit override (non-numeric) must fall back to the computed
# default (with a WARN to stderr, not asserted here) rather than propagating
# a bad value or crashing the script.
export CODERABBIT_NO_TRIGGER_TIMEOUT="not-a-number"
actual="$(coderabbit_resolve_no_trigger_timeout 180 2>/dev/null)"
run_test "no_trigger_resolve_invalid_override_falls_back_to_default" "90" "$actual"
unset CODERABBIT_NO_TRIGGER_TIMEOUT

# A zero explicit override (fails the `-le 0` guard) must also fall back.
export CODERABBIT_NO_TRIGGER_TIMEOUT=0
actual="$(coderabbit_resolve_no_trigger_timeout 1200 2>/dev/null)"
run_test "no_trigger_resolve_zero_override_falls_back_to_default" "180" "$actual"
unset CODERABBIT_NO_TRIGGER_TIMEOUT

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
