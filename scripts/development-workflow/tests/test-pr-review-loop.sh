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
# Run from an immutable snapshot (issue #1562)
# ---------------------------------------------------------------------------
#
# Bash reads a script incrementally rather than loading it whole, so editing
# this file while a run is in flight makes the running shell pick up part of
# the new text at whatever offset it has reached. During the #1531 work that
# produced a run reporting a pass/fail count matching neither the old file nor
# the new one, with nothing to indicate anything had happened. At ~13 minutes
# per run the temptation to edit while waiting is constant, which makes this a
# question of when rather than whether.
#
# So the harness copies itself to a temp file and re-executes from there. The
# copy is a single atomic-enough read at startup; once running, edits to the
# working-tree file cannot reach it.
#
# The obvious manual workaround — copy it somewhere immutable and run that —
# does not work on its own, because the repo root is resolved via git from the
# script's own location. TEST_PR_REVIEW_LOOP_ORIGIN carries the original path
# across the re-exec so root resolution still anchors to the real checkout.
#
# --area composes with the snapshot rather than needing its own machinery: the
# areas are contiguous line ranges in a linear script, so a filtered run is
# just a snapshot built from the shared preamble, the selected ranges, and the
# summary footer. Nothing in the 13k-line body has to be restructured or
# wrapped in conditionals.
#
# Why it is worth having (measured on a clean tree):
#   * whole suite            210s
#   * Area 13 alone          197s  — 94%, from 156 codex-github-reviewer.sh
#                                    invocations that each really sleep
#   * all 27 other areas     ~13s
# So iterating on anything other than Area 13 goes from minutes to seconds.
if [ "${TEST_PR_REVIEW_LOOP_SNAPSHOT:-0}" != "1" ]; then
  _area_filter=""
  _list_areas=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --area)
        [ $# -ge 2 ] || { echo "ERROR: --area requires a value" >&2; exit 2; }
        [ -n "$2" ] || { echo "ERROR: --area requires a non-empty value" >&2; exit 2; }
        _area_filter="${_area_filter}${_area_filter:+,}$2"
        shift 2
        ;;
      --area=*)
        # Reject an empty value. Appending an empty token left _area_filter
        # empty, which the snapshot step reads as "unfiltered" — so `--area=`
        # asked for a filter and silently got the full run instead.
        if [ -z "${1#--area=}" ]; then
          echo "ERROR: --area= requires a value" >&2
          exit 2
        fi
        _area_filter="${_area_filter}${_area_filter:+,}${1#--area=}"
        shift
        ;;
      --list-areas) _list_areas=1; shift ;;
      -h|--help)
        cat <<'USAGE'
Usage: bash test-pr-review-loop.sh [--area <name>]... [--list-areas]

  --area <name>   Run only matching areas. Matches the area's number or any
                  substring of its title, case-insensitively; repeatable, and
                  a comma-separated list is accepted. Examples:
                    --area 13
                    --area haystack
                    --area 0a --area 1
  --list-areas    Print the area names with their line ranges and exit.

With no arguments the whole suite runs.
USAGE
        exit 0
        ;;
      *) echo "ERROR: unknown argument '$1'" >&2; exit 2 ;;
    esac
  done

  # Honour a pre-set origin so a copy of this file placed outside the checkout
  # still resolves the repo root — the workaround issue #1562 records as not
  # working. The snapshot below makes the copy unnecessary, but someone holding
  # an out-of-tree copy should not be met with "fatal: not a git repository".
  if [ -n "${TEST_PR_REVIEW_LOOP_ORIGIN:-}" ]; then
    if [ ! -f "$TEST_PR_REVIEW_LOOP_ORIGIN" ]; then
      echo "ERROR: TEST_PR_REVIEW_LOOP_ORIGIN does not exist: $TEST_PR_REVIEW_LOOP_ORIGIN" >&2
      exit 2
    fi
    _origin_dir="$(CDPATH='' cd -- "$(dirname -- "$TEST_PR_REVIEW_LOOP_ORIGIN")" && pwd)"
    _self="$_origin_dir/$(basename "$TEST_PR_REVIEW_LOOP_ORIGIN")"
  else
    _origin_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
    _self="$_origin_dir/$(basename "$0")"
  fi

  if [ "$_list_areas" -eq 1 ]; then
    awk '
      /^echo "=== / {
        line=$0
        sub(/^echo "=== /, "", line)
        sub(/ ==="$/, "", line)
        if (prev != "") printf "  %-70s lines %d-%d\n", prev, pstart, NR-1
        prev=line; pstart=NR
      }
      END { if (prev != "") printf "  %-70s lines %d-%d\n", prev, pstart, NR }
    ' "$_self"
    exit 0
  fi

  _snapshot="$(mktemp -t test-pr-review-loop.XXXXXX)"
  if [ -z "$_area_filter" ]; then
    if ! cat "$_self" > "$_snapshot"; then
      rm -f "$_snapshot"
      echo "ERROR: could not snapshot the test harness for execution" >&2
      exit 2
    fi
  else
    # mktemp rather than a $$-derived name: /tmp is world-writable, so a
    # predictable path can be pre-created as a symlink and redirect this write
    # to a file of someone else's choosing. PIDs also recur.
    if ! _filter_err="$(mktemp -t test-pr-review-loop-filter.XXXXXX)" \
       || [ -z "$_filter_err" ]; then
      echo "ERROR: could not create a temp file for the area-filter diagnostics" >&2
      exit 2
    fi
    # Preamble (everything before the first area) + selected areas + footer.
    if ! awk -v filter="$_area_filter" '
      function selected(title,   n, i, pat, lt) {
        n = split(filter, pats, ",")
        lt = tolower(title)
        for (i = 1; i <= n; i++) {
          pat = tolower(pats[i])
          gsub(/^[ \t]+|[ \t]+$/, "", pat)
          if (pat == "") continue
          # A bare number must match the area number exactly, so --area 1 does
          # not also drag in 10, 10b, 12, and 13.
          if (pat ~ /^[0-9]+[a-z]?$/) {
            if (tolower(title) ~ ("^area " pat ":")) return 1
          } else if (index(lt, pat) > 0) {
            return 1
          }
        }
        return 0
      }
      BEGIN { emit = 1; matched = 0; footer = 0 }
      # The summary block must survive every filter: it prints the counts and
      # carries the [ "$FAIL_COUNT" -eq 0 ] test that gives the run its exit
      # status. Dropping it made a filtered run with failures still exit 0.
      /^# Summary$/ { footer = 1 }
      footer { print; next }
      /^echo "=== / {
        title = $0
        sub(/^echo "=== /, "", title)
        sub(/ ==="$/, "", title)
        emit = selected(title)
        if (emit) matched = 1
        seen_area = 1
      }
      /^# -+$/ && seen_area && !emit { next }
      { if (emit) print }
      END {
        if (!matched) {
          print "NO_AREA_MATCHED" > "/dev/stderr"
          exit 3
        }
      }
    ' "$_self" > "$_snapshot" 2>"$_filter_err"; then
      rm -f "$_snapshot"
      if grep -q NO_AREA_MATCHED "$_filter_err" 2>/dev/null; then
        echo "ERROR: no area matched '--area $_area_filter'." >&2
        echo "  Run with --list-areas to see the available areas." >&2
      fi
      rm -f "$_filter_err"
      exit 2
    fi
    rm -f "$_filter_err"
    echo "INFO: running filtered areas: $_area_filter" >&2
  fi

  TEST_PR_REVIEW_LOOP_SNAPSHOT=1 \
  TEST_PR_REVIEW_LOOP_ORIGIN="$_self" \
  TEST_PR_REVIEW_LOOP_AREA_FILTER="$_area_filter" \
    bash "$_snapshot" 
  _rc=$?
  rm -f "$_snapshot"
  exit "$_rc"
fi

# ---------------------------------------------------------------------------
# Locate repository root (works inside worktrees and normal checkouts).
# ---------------------------------------------------------------------------
# Prefer the pre-re-exec origin: $0 is the snapshot in a temp directory, which
# is not inside any checkout.
if [ -n "${TEST_PR_REVIEW_LOOP_ORIGIN:-}" ]; then
  SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$TEST_PR_REVIEW_LOOP_ORIGIN")" && pwd)"
else
  SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
fi
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

# Preserved before the mocks are prepended, so a test that needs to invoke a
# real tool (or re-enter this harness) can do so with the genuine PATH. Without
# it, a nested run picks up the mock git and cannot resolve the repo root.
TEST_PR_REVIEW_LOOP_REAL_PATH="$PATH"
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

unset CODEX_GITHUB_MAX_WAIT CODEX_GITHUB_POLL_INTERVAL
run_test "codex_github_default_max_wait" "1800" "$(codex_github_default_max_wait)"
run_test "codex_github_default_poll_interval" "60" "$(codex_github_default_poll_interval 1800)"
run_test "codex_github_poll_interval_clamps_to_budget" "15" "$(codex_github_default_poll_interval 30)"

CODEX_GITHUB_MAX_WAIT=2400
CODEX_GITHUB_POLL_INTERVAL=90
export CODEX_GITHUB_MAX_WAIT CODEX_GITHUB_POLL_INTERVAL
run_test "codex_github_env_override_max_wait" "2400" "$(codex_github_default_max_wait)"
run_test "codex_github_env_override_poll_interval" "90" "$(codex_github_default_poll_interval 2400)"

CODEX_GITHUB_MAX_WAIT=bad
CODEX_GITHUB_POLL_INTERVAL=bad
export CODEX_GITHUB_MAX_WAIT CODEX_GITHUB_POLL_INTERVAL
_codex_timeout_output="$(codex_github_default_max_wait 2>/dev/null)"
_codex_poll_output="$(codex_github_default_poll_interval 1800 2>/dev/null)"
run_test "codex_github_invalid_env_falls_back_max_wait" "1800" "$_codex_timeout_output"
run_test "codex_github_invalid_env_falls_back_poll_interval" "60" "$_codex_poll_output"

declare -a platforms=("pr-agent" "codex-github")
declare -a phase_after_clean_platforms=()
if codex_github_defaults_should_apply; then
  _codex_defaults_apply_active="yes"
else
  _codex_defaults_apply_active="no"
fi
run_test "codex_github_defaults_apply_active_platform" "yes" "$_codex_defaults_apply_active"

declare -a platforms=("pr-agent")
declare -a phase_after_clean_platforms=("codex-github")
if codex_github_defaults_should_apply; then
  _codex_defaults_apply_telemetry="yes"
else
  _codex_defaults_apply_telemetry="no"
fi
run_test "codex_github_defaults_ignore_telemetry_only_platform" "no" "$_codex_defaults_apply_telemetry"

platforms=()
phase_after_clean_platforms=()
unset CODEX_GITHUB_MAX_WAIT CODEX_GITHUB_POLL_INTERVAL _codex_timeout_output _codex_poll_output _codex_defaults_apply_active _codex_defaults_apply_telemetry

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
# JSON that the real GraphQL query would return after --jq (the --jq filter is
# `.data.repository.pullRequest`, so MOCK_GH_OUTPUT must be an object with a
# top-level "reviewThreads" key — and, for provisional-mode cases, a top-level
# "commits" key holding the PR head commit's committedDate).
#
# Important: GitHub's GraphQL API returns author.login WITHOUT the "[bot]" suffix
# (e.g. "coderabbitai", not "coderabbitai[bot]"). The aggregate gate strips the
# "[bot]" suffix from bot_login_for_platform() output before adding to
# unresolved_bot_logins, so check_unresolved_threads always receives login strings
# without the "[bot]" suffix. All test cases below use sanitized login strings.
#
# check_unresolved_threads takes a required "mode" argument ("strict" or
# "provisional") as its third positional parameter, before the bot_logins
# varargs. Every call below passes it explicitly.
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
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai")"
run_test "unresolved_threads_none" "0" "$actual"

# test: one unresolved bot thread — count should be 1
# GraphQL author.login is "coderabbitai" (no "[bot]" suffix — stripped by caller)
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Blocking issue"}]}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai")"
run_test "unresolved_threads_one_bot" "1" "$actual"

# test: one resolved bot thread — count should be 0
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":true,"firstComment":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Blocking issue"}]}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai")"
run_test "unresolved_threads_resolved_skipped" "0" "$actual"

# test: bot thread with "✅ Addressed" in body — count should be 0
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"coderabbitai"},"body":"✅ Addressed — fixed in latest commit"}]}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai")"
run_test "unresolved_threads_addressed_body_skipped" "0" "$actual"

# test: human-authored thread unresolved — count should be 0 (bot-only filter)
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"humanreview"},"body":"Please change this"}]}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai")"
run_test "unresolved_threads_human_ignored" "0" "$actual"

# test: two bot threads, one resolved, one not — count should be 1
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":true,"firstComment":{"nodes":[{"author":{"login":"coderabbitai"},"body":"First finding"}]}},{"id":"RT2","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Second finding"}]}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai")"
run_test "unresolved_threads_mixed_resolved" "1" "$actual"

# test: [bot]-suffix login NOT matched (gate strips suffix; bare login is required)
# Passing "coderabbitai[bot]" should NOT match GraphQL "coderabbitai" — returns 0.
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Blocking issue"}]}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" strict "coderabbitai[bot]")"
run_test "unresolved_threads_bot_suffix_no_match" "0" "$actual"

# test: GraphQL API failure (exit 1 from gh) — function should return exit 3
export MOCK_GH_EXIT=1
actual_exit=0
check_unresolved_threads "1" "owner/repo" strict "coderabbitai" > /dev/null 2>&1 || actual_exit=$?
run_test "unresolved_threads_graphql_failure_exit3" "3" "$actual_exit"
unset MOCK_GH_EXIT

# test: unrecognized mode value fails safe to strict — a reply-after-head-commit
# must NOT be treated as provisionally addressed when mode is misspelled/garbage.
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]},"lastComment":{"nodes":[{"author":{"login":"humanreview"},"body":"fixed","createdAt":"2026-08-21T02:00:00Z"}]}}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-08-21T01:00:00Z"}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" bogus-mode "chatgpt-codex-connector")"
run_test "unresolved_threads_unrecognized_mode_fails_safe_to_strict" "1" "$actual"

# ---------------------------------------------------------------------------
# Area 6b: check_unresolved_threads mode=provisional (#1508)
#
# A replied-but-unresolved thread must not block phase-1 gates (run_codex_
# github_review, run_claude_code_action_review) from re-triggering a review
# when the reply came from a non-bot author AFTER the current PR head commit
# — this is the "fixer pushed and replied but has not yet called
# resolveReviewThread" state described in issue #1508. Every other caller
# (the aggregate clean gate, coderabbit_thread_gate_clean, the post-trigger
# findings recount, and the post-clean recheck) keeps using mode=strict, so
# these provisional-mode semantics can only ever make check_unresolved_threads
# return a SMALLER count than strict mode for the same input — never used by
# anything that decides RESULT=clean. Confirmed at the call-site level in the
# "call-site mode audit" test below.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 6b: check_unresolved_threads mode=provisional (#1508) ==="

# Direction 1 (the reported bug): a thread replied to by a human AFTER the
# head commit was pushed must NOT block re-review in provisional mode — count
# should be 0, even though isResolved is still false (no resolveReviewThread
# call was made).
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]},"lastComment":{"nodes":[{"author":{"login":"humanreview"},"body":"Fixed in the latest push, see commit abc123","createdAt":"2026-08-21T02:00:00Z"}]}}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-08-21T01:00:00Z"}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" provisional "chatgpt-codex-connector")"
run_test "unresolved_threads_provisional_reply_after_head_not_blocking" "0" "$actual"

# The SAME fixture under mode=strict must still count as unresolved (1) —
# this is the load-bearing guarantee that provisional mode cannot leak into
# any RESULT=clean decision: strict mode ignores the reply entirely and
# requires true GraphQL resolution.
actual="$(check_unresolved_threads "1" "owner/repo" strict "chatgpt-codex-connector")"
run_test "unresolved_threads_strict_still_blocks_same_replied_thread" "1" "$actual"

# Direction 2 (must not open the false-clean class, #1531/#1437): a reply
# posted BEFORE the head commit (i.e. the fixer pushed AFTER replying, or the
# reply predates the fix entirely) must still count as unresolved even in
# provisional mode — an old reply is not evidence the current HEAD was
# addressed.
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]},"lastComment":{"nodes":[{"author":{"login":"humanreview"},"body":"looking into it","createdAt":"2026-08-20T23:00:00Z"}]}}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-08-21T01:00:00Z"}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" provisional "chatgpt-codex-connector")"
run_test "unresolved_threads_provisional_reply_before_head_still_blocks" "1" "$actual"

# Direction 2 (continued): a reply from the bot ITSELF (e.g. a second bot
# comment in the thread) must not count as a "human/agent reply" — still
# unresolved even in provisional mode.
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]},"lastComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"still an issue","createdAt":"2026-08-21T02:00:00Z"}]}}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-08-21T01:00:00Z"}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" provisional "chatgpt-codex-connector")"
run_test "unresolved_threads_provisional_bot_last_comment_still_blocks" "1" "$actual"

# Direction 2 (continued): with no lastComment data at all (e.g. thread has
# exactly one comment — the bot's own finding, never replied to), provisional
# mode must behave exactly like strict — still unresolved.
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":false,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]}}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-08-21T01:00:00Z"}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" provisional "chatgpt-codex-connector")"
run_test "unresolved_threads_provisional_no_reply_still_blocks" "1" "$actual"

# Sanity: true resolution (isResolved=true) still counts as resolved under
# provisional mode exactly as under strict — provisional mode only ADDS a
# relaxation, it never removes the existing strict checks.
export MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT1","isResolved":true,"firstComment":{"nodes":[{"author":{"login":"chatgpt-codex-connector"},"body":"Blocking issue"}]}}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-08-21T01:00:00Z"}}]}}'
actual="$(check_unresolved_threads "1" "owner/repo" provisional "chatgpt-codex-connector")"
run_test "unresolved_threads_provisional_true_resolution_still_clean" "0" "$actual"
unset MOCK_GH_OUTPUT

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

# Test 10.5: the summary is posted (via _post_review_summary) before the
# needs_fixes exit branch runs, and that branch simply selects exit 1.
#
# UPDATED for #1502's dual-cap single-RESULT-line fix: _post_review_summary
# now runs ONCE, before the whole `case "$aggregate_result" in` statement
# (so a persistence failure can correct aggregate_result to escalate BEFORE
# RESULT= is ever printed — see the "Single-RESULT-line fix" tests below
# for why). The needs_fixes branch itself no longer calls
# _post_review_summary directly; it only exits 1 for whatever
# aggregate_result settled to after that shared persistence step.
_post_summary_precedes_case="$(awk '
  /_post_review_summary "\$aggregate_result" "\$aggregate_reason"/ {found_call=1}
  /^case "\$aggregate_result" in/ {print (found_call == 1) ? "yes" : "no"; exit}
' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
run_test "main_needs_fixes_summary_posted_before_case_statement" "yes" "$_post_summary_precedes_case"
_needs_fixes_case_block="$(awk '
  /^  needs_fixes\)/ {capture=1}
  capture {print}
  capture && /^    ;;/ {exit}
' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
if grep -qF 'exit 1' <<<"$_needs_fixes_case_block" \
    && ! grep -qF '_post_review_summary' <<<"$_needs_fixes_case_block"; then
  _needs_fixes_main_summary_count=1
else
  _needs_fixes_main_summary_count=0
fi
run_test "main_needs_fixes_exit_posts_summary" "1" "$_needs_fixes_main_summary_count"
unset _post_summary_precedes_case _needs_fixes_case_block _needs_fixes_main_summary_count

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
# _post_review_summary now returns non-zero on a read failure too (#1502
# dual-cap follow-up), even when the write succeeds — guard the bare call
# with `|| true` since this test only cares about the rendered body, not
# the return code (covered separately by the read-failure-return tests).
_post_review_summary "clean" "" "bugbot (clean)" "0" "0" || true
if [ -n "${_summary_read_failed_body_capture:-}" ] \
    && grep -q "comment_read_failed" "$_summary_read_failed_body_capture"; then
  _summary_read_failed_history="yes"
else
  _summary_read_failed_history="no"
fi
run_test "summary_comment_read_failure_history_unavailable" "yes" "$_summary_read_failed_history"
rm -f "$_summary_read_failed_body_capture"

# AC / regression (Codex finding on PR #1507: "preserve dispatches across
# unavailable-ledger recovery"): _post_review_summary must return non-zero
# on a READ failure even when the WRITE succeeds (MOCK_GH_EXIT=0 above), not
# only when the write itself fails. A read failure means this cycle's own
# entry may have been silently folded into an "unavailable" stub that never
# gets appended (append_safe=0), even though the stub POST succeeds — the
# write succeeding is not sufficient evidence the cycle is countable.
if ! _summary_read_failed_body_capture_2="$(mktemp)"; then
  echo "ERROR: failed to allocate second read-failure summary body capture temp file" >&2
  exit 1
fi
export MOCK_GH_BODY_CAPTURE="$_summary_read_failed_body_capture_2"
_post_summary_read_failure_exit=0
_post_review_summary "needs_fixes" "haystack_blocking_findings" "haystack (needs_fixes)" "1" "0"   || _post_summary_read_failure_exit=$?
run_test "summary_read_failure_returns_nonzero_even_when_write_succeeds" "1"   "$_post_summary_read_failure_exit"
rm -f "$_summary_read_failed_body_capture_2"
unset _summary_read_failed_body_capture_2 _post_summary_read_failure_exit
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
# shellcheck disable=SC2034 # read via "${unresolved_thread_count:-0}" inside
# reviewer_loop_history_build_entry (pr-review-loop.sh), which ShellCheck
# cannot trace across the dynamic HARNESS_MODE=1 source above.
unresolved_thread_count=0
# shellcheck disable=SC2034 # same as unresolved_thread_count above.
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
# Area 10c: reviewer-loop max_cycles / max_total_cycles enforcement (#1502,
# dual-cap follow-up per operator decision on PR #1507's review)
#
# reviewer_loop_history_entries_count, reviewer_loop_resolve_max_cycles,
# reviewer_loop_resolve_max_total_cycles, reviewer_loop_cap_exceeded,
# reviewer_loop_cycle_count_unavailable_should_escalate,
# reviewer_loop_resolve_cycle_counts, and reviewer_loop_resolve_run_id are
# all defined before the HARNESS_MODE return point and are therefore
# callable directly, like restore_regression_label_if_missing in Area 11.
#
# Protocol 91:1719 documents a PER-RUN cap ("Initialize cycle = 0 once per
# orchestration run ... escalate when the run reaches max_cycles"). A
# per-run-only cap leaves total effort unbounded across many resumed
# orchestration runs, so a second, never-resetting LIFETIME ceiling is
# layered on top. These tests exercise the actual enforcement functions for
# both axes, not simulated logic.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 10c: reviewer-loop max_cycles / max_total_cycles enforcement (#1502) ==="

# --- reviewer_loop_resolve_run_id ---

unset PR_REVIEW_LOOP_RUN_ID
# Note: a `case` statement directly inside `$( ... )` fails to parse on
# bash 3.2 (macOS default) — the `)` closing a case pattern is misread as
# the command-substitution terminator. Use `[[ ... == prefix* ]]` instead.
run_test "run_id_auto_generated_has_prefix" "yes" "$(
  _rid="$(reviewer_loop_resolve_run_id)"
  if [[ "$_rid" == auto-* ]]; then echo yes; else echo no; fi
)"
run_test "run_id_explicit_env_honored_verbatim" "my-stable-run-42" \
  "$(PR_REVIEW_LOOP_RUN_ID=my-stable-run-42 reviewer_loop_resolve_run_id)"

# --- reviewer_loop_history_entries_count <body> <run_id> ---
# Counts Protocol 91's per-run `cycle` value (run_count, scoped to the
# queried run_id) and a separate never-resetting lifetime_count. Both only
# count prior entries whose result is needs_fixes or needs_rerun, deduped
# by distinct head_sha (unchanged refinements from the earlier review
# round — see the block comment above reviewer_loop_history_entries_count
# in pr-review-loop.sh).

run_test "cycles_entries_count_empty_body" "0 0 available" \
  "$(reviewer_loop_history_entries_count "" "run-x")"

_mc_no_marker_body="### Automated Reviewer Loop Summary
*Posted automatically by \`pr-review-loop.sh\`.*"
run_test "cycles_entries_count_no_marker" "0 0 available" \
  "$(reviewer_loop_history_entries_count "$_mc_no_marker_body" "run-x")"

_mc_marker_no_json_body=$'### Automated Reviewer Loop Summary\n<!-- reviewer-loop-history:v1 -->\nNo fenced JSON block here.'
run_test "cycles_entries_count_marker_no_json" "-1 -1 unavailable" \
  "$(reviewer_loop_history_entries_count "$_mc_marker_no_json_body" "run-x")"

# 10 fixer-dispatch-triggering entries (result=needs_fixes), each with a
# DISTINCT head_sha, all recorded under run_id "run-A". Queried with the
# SAME run_id: both lifetime and per-run counts are 10 (at the default
# per-run cap of 10). Queried with a DIFFERENT run_id ("run-B", simulating
# a new orchestration run): lifetime is still 10 (never resets), but the
# per-run count is 0 (fresh run boundary) — this is the core per-run-reset
# proof (AC: "per-run reset across a run boundary").
_mc_ten_dispatch_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [range(1;11) | {iteration: ., head_sha: ("sha-" + (.|tostring)), result: "needs_fixes", run_id: "run-A"}]
}')"
_mc_ten_dispatch_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_mc_ten_dispatch_payload" | jq '.')
\`\`\`"
run_test "cycles_entries_count_same_run_id_counts_both_axes" "10 10 available" \
  "$(reviewer_loop_history_entries_count "$_mc_ten_dispatch_body" "run-A")"
run_test "cycles_entries_count_new_run_id_resets_per_run_only" "10 0 available" \
  "$(reviewer_loop_history_entries_count "$_mc_ten_dispatch_body" "run-B")"

# Mixed-result ledger: 2 needs_fixes + 1 clean + 1 skipped = 4 total entries,
# but only the 2 needs_fixes entries (both run_id "run-A") represent an
# actual fixer dispatch.
_mc_mixed_result_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [
    {iteration: 1, head_sha: "sha-1", result: "needs_fixes", run_id: "run-A"},
    {iteration: 2, head_sha: "sha-1", result: "clean", run_id: "run-A"},
    {iteration: 3, head_sha: "sha-2", result: "skipped", run_id: "run-A"},
    {iteration: 4, head_sha: "sha-3", result: "needs_fixes", run_id: "run-A"}
  ]
}')"
_mc_mixed_result_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_mc_mixed_result_payload" | jq '.')
\`\`\`"
run_test "cycles_entries_count_only_counts_fixer_dispatch_results" "2 2 available" \
  "$(reviewer_loop_history_entries_count "$_mc_mixed_result_body" "run-A")"

# Duplicate-head-sha dedup (still correct on both axes): 3 needs_fixes
# entries under run_id "run-A", 2 of which share the same head_sha (no fix
# actually applied between them). Distinct-head-sha count must be 2, not 3,
# on both the lifetime and per-run axes.
_mc_dup_head_sha_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [
    {iteration: 1, head_sha: "sha-A", result: "needs_fixes", run_id: "run-A"},
    {iteration: 2, head_sha: "sha-A", result: "needs_fixes", run_id: "run-A"},
    {iteration: 3, head_sha: "sha-B", result: "needs_fixes", run_id: "run-A"}
  ]
}')"
_mc_dup_head_sha_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_mc_dup_head_sha_payload" | jq '.')
\`\`\`"
run_test "cycles_entries_count_dedups_duplicate_head_sha" "2 2 available" \
  "$(reviewer_loop_history_entries_count "$_mc_dup_head_sha_body" "run-A")"

# AC / regression (Codex finding on PR #1507): a needs_rerun entry
# IMMEDIATELY FOLLOWED by a needs_fixes entry on the SAME resulting
# head_sha must count as TWO distinct dispatches, not one — deduping by
# head_sha alone would incorrectly merge "PR-Agent's auto-push evaluation
# completed a fix cycle" (needs_rerun) with "a different reviewer found a
# NEW issue on that same resulting state" (needs_fixes), letting more than
# the configured number of real fixes happen before either cap fires.
# Keying on (head_sha, result) instead of head_sha alone fixes this while
# still deduping TRUE duplicates (same head_sha AND same result).
_mc_rerun_then_fixes_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [
    {iteration: 1, head_sha: "H1", result: "needs_rerun", run_id: "run-A"},
    {iteration: 2, head_sha: "H1", result: "needs_fixes", run_id: "run-A"}
  ]
}')"
_mc_rerun_then_fixes_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s
' "$_mc_rerun_then_fixes_payload" | jq '.')
\`\`\`"
run_test "cycles_entries_count_rerun_then_fixes_same_sha_counts_two" "2 2 available" \
  "$(reviewer_loop_history_entries_count "$_mc_rerun_then_fixes_body" "run-A")"

# An entry with an empty/unresolved head_sha must not be counted at all on
# either axis.
_mc_empty_head_sha_payload='{
  "schema": "reviewer_loop_history.v1",
  "history_status": "available",
  "entries": [
    {"iteration": 1, "head_sha": "", "result": "needs_fixes", "run_id": "run-A"},
    {"iteration": 2, "head_sha": "", "result": "needs_fixes", "run_id": "run-A"},
    {"iteration": 3, "head_sha": "sha-C", "result": "needs_fixes", "run_id": "run-A"}
  ]
}'
_mc_empty_head_sha_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_mc_empty_head_sha_payload" | jq '.')
\`\`\`"
run_test "cycles_entries_count_excludes_empty_head_sha" "1 1 available" \
  "$(reviewer_loop_history_entries_count "$_mc_empty_head_sha_body" "run-A")"

# AC: "back-compat entries lacking a run id" — entries written before
# run_id existed (no run_id key at all). They must count toward the
# lifetime axis (real historical fixer dispatches) but can never satisfy
# ANY per-run query, regardless of which run_id is queried — including a
# query with an EMPTY run_id, which must not accidentally match via
# "(.run_id // "") == $runId" both sides being "".
_mc_back_compat_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [range(1;6) | {iteration: ., head_sha: ("sha-old-" + (.|tostring)), result: "needs_fixes"}]
}')"
_mc_back_compat_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_mc_back_compat_payload" | jq '.')
\`\`\`"
run_test "cycles_entries_count_back_compat_counts_lifetime_only" "5 0 available" \
  "$(reviewer_loop_history_entries_count "$_mc_back_compat_body" "run-fresh")"
run_test "cycles_entries_count_back_compat_empty_run_id_query_does_not_match" "5 0 available" \
  "$(reviewer_loop_history_entries_count "$_mc_back_compat_body" "")"

_mc_persisted_unavailable_body=$'### Automated Reviewer Loop Summary\n<!-- reviewer-loop-history:v1 -->\n```json\n{"schema":"reviewer_loop_history.v1","history_status":"unavailable","history_unavailable_reason":"comment_read_failed","entries":[]}\n```\n'
run_test "cycles_entries_count_persisted_unavailable" "-1 -1 unavailable" \
  "$(reviewer_loop_history_entries_count "$_mc_persisted_unavailable_body" "run-x")"

_mc_malformed_body=$'### Automated Reviewer Loop Summary\n<!-- reviewer-loop-history:v1 -->\n```json\n{ not json\n```\n'
run_test "cycles_entries_count_malformed" "-1 -1 unavailable" \
  "$(reviewer_loop_history_entries_count "$_mc_malformed_body" "run-x")"

_mc_wrong_schema_body=$'### Automated Reviewer Loop Summary\n<!-- reviewer-loop-history:v1 -->\n```json\n{"schema":"other.v1","entries":[]}\n```\n'
run_test "cycles_entries_count_wrong_schema" "-1 -1 unavailable" \
  "$(reviewer_loop_history_entries_count "$_mc_wrong_schema_body" "run-x")"

# --- reviewer_loop_resolve_max_cycles (per-run cap) ---
# PR_REVIEW_LOOP_MAX_CYCLES must be unset (not just empty) in this shell for
# the "no override" cases — `env -u` cannot be used here because
# reviewer_loop_resolve_max_cycles is a shell function, not an external
# command, and env only executes external programs.
unset PR_REVIEW_LOOP_MAX_CYCLES

run_test "cycles_resolve_max_default" "10" \
  "$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
run_test "cycles_resolve_max_from_config" "7" \
  "$(reviewer_loop_resolve_max_cycles "7" 2>/dev/null)"
run_test "cycles_resolve_max_env_overrides_config" "3" \
  "$(PR_REVIEW_LOOP_MAX_CYCLES=3 reviewer_loop_resolve_max_cycles "7" 2>/dev/null)"
run_test "cycles_resolve_max_invalid_config_defaults" "10" \
  "$(reviewer_loop_resolve_max_cycles "not-a-number" 2>/dev/null)"
run_test "cycles_resolve_max_invalid_config_warns" "yes" "$(
  # Capture stderr into a variable first, then grep the variable — piping
  # directly into `grep -q` risks a SIGPIPE false-negative under pipefail.
  _mc_warn_stderr="$(reviewer_loop_resolve_max_cycles "not-a-number" 2>&1 >/dev/null)"
  if printf '%s\n' "$_mc_warn_stderr" | grep -q "WARN.*not a positive integer"; then
    echo yes
  else
    echo no
  fi
)"
run_test "cycles_resolve_max_zero_invalid_defaults" "10" \
  "$(PR_REVIEW_LOOP_MAX_CYCLES=0 reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
run_test "cycles_resolve_max_out_of_range_defaults" "10" \
  "$(PR_REVIEW_LOOP_MAX_CYCLES=99999999999999999999 reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
run_test "cycles_resolve_max_six_digit_boundary_accepted" "999999" \
  "$(PR_REVIEW_LOOP_MAX_CYCLES=999999 reviewer_loop_resolve_max_cycles "" 2>/dev/null)"

# --- reviewer_loop_resolve_max_total_cycles (lifetime ceiling) ---
# Mirrors reviewer_loop_resolve_max_cycles's validation exactly (same
# regex, same range), on the sibling env var / config key, default 25.
unset PR_REVIEW_LOOP_MAX_TOTAL_CYCLES

run_test "total_cycles_resolve_max_default" "25" \
  "$(reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
run_test "total_cycles_resolve_max_from_config" "40" \
  "$(reviewer_loop_resolve_max_total_cycles "40" 2>/dev/null)"
run_test "total_cycles_resolve_max_env_overrides_config" "12" \
  "$(PR_REVIEW_LOOP_MAX_TOTAL_CYCLES=12 reviewer_loop_resolve_max_total_cycles "40" 2>/dev/null)"
run_test "total_cycles_resolve_max_invalid_config_defaults" "25" \
  "$(reviewer_loop_resolve_max_total_cycles "not-a-number" 2>/dev/null)"
run_test "total_cycles_resolve_max_invalid_config_warns" "yes" "$(
  _mc_warn_stderr="$(reviewer_loop_resolve_max_total_cycles "not-a-number" 2>&1 >/dev/null)"
  if printf '%s\n' "$_mc_warn_stderr" | grep -q "WARN.*not a positive integer"; then
    echo yes
  else
    echo no
  fi
)"
run_test "total_cycles_resolve_max_zero_invalid_defaults" "25" \
  "$(PR_REVIEW_LOOP_MAX_TOTAL_CYCLES=0 reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
run_test "total_cycles_resolve_max_out_of_range_defaults" "25" \
  "$(PR_REVIEW_LOOP_MAX_TOTAL_CYCLES=99999999999999999999 reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
run_test "total_cycles_resolve_max_six_digit_boundary_accepted" "999999" \
  "$(PR_REVIEW_LOOP_MAX_TOTAL_CYCLES=999999 reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
# The two resolvers must be independently configurable (distinct env vars /
# config keys) — setting one must not affect the other's default.
run_test "cycles_max_cycles_and_max_total_cycles_independent" "10 25" "$(
  unset PR_REVIEW_LOOP_MAX_CYCLES PR_REVIEW_LOOP_MAX_TOTAL_CYCLES
  _m1="$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
  _m2="$(reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
  echo "$_m1 $_m2"
)"

# --- reviewer_loop_cap_exceeded (generic; reused for both axes) ---
# AC: "reaching the cap escalates" / "staying under it does not".

run_test "cycles_cap_under_not_exceeded" "no" \
  "$(reviewer_loop_cap_exceeded 9 10 needs_fixes && echo yes || echo no)"
run_test "cycles_cap_at_limit_exceeded" "yes" \
  "$(reviewer_loop_cap_exceeded 10 10 needs_fixes && echo yes || echo no)"
run_test "cycles_cap_over_limit_exceeded" "yes" \
  "$(reviewer_loop_cap_exceeded 11 10 needs_fixes && echo yes || echo no)"
run_test "cycles_cap_needs_rerun_bounded_by_same_counter" "yes" \
  "$(reviewer_loop_cap_exceeded 10 10 needs_rerun && echo yes || echo no)"
run_test "cycles_cap_clean_never_overridden" "no" \
  "$(reviewer_loop_cap_exceeded 999 10 clean && echo yes || echo no)"
run_test "cycles_cap_already_escalate_not_retriggered" "no" \
  "$(reviewer_loop_cap_exceeded 999 10 escalate && echo yes || echo no)"
run_test "cycles_cap_unknown_count_fails_open" "no" \
  "$(reviewer_loop_cap_exceeded -1 10 needs_fixes && echo yes || echo no)"
# Reused directly against the lifetime axis (default 25) — same function,
# different (count, cap) pair.
run_test "total_cycles_cap_under_not_exceeded" "no" \
  "$(reviewer_loop_cap_exceeded 24 25 needs_fixes && echo yes || echo no)"
run_test "total_cycles_cap_at_limit_exceeded" "yes" \
  "$(reviewer_loop_cap_exceeded 25 25 needs_fixes && echo yes || echo no)"

# --- reviewer_loop_resolve_cycle_counts (mocked gh) ---

unset MOCK_GH_COMMENTS_OUTPUT MOCK_GH_COMMENTS_EXIT MOCK_GH_EXIT

run_test "cycles_resolve_counts_no_pr_number" "-1 -1" \
  "$(reviewer_loop_resolve_cycle_counts "" "run-x")"

export MOCK_GH_COMMENTS_OUTPUT="[]"
run_test "cycles_resolve_counts_first_run_is_zero_zero" "0 0" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-x" 2>/dev/null)"
unset MOCK_GH_COMMENTS_OUTPUT

# AC / regression (Codex finding on PR #1507): when the OLDEST of two
# summary comments has available history (3 needs_fixes entries) but the
# NEWEST has history_status=unavailable, reviewer_loop_resolve_cycle_counts
# must report "-1 -1" (fail closed on the newest ledger's true status) —
# NOT fall back to the older comment's stale 3/3 count the way the RENDER
# path's reviewer_loop_history_select_summary_record intentionally does.
_mc_stale_available_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [range(1;4) | {iteration: ., head_sha: ("sha-" + (.|tostring)), result: "needs_fixes", run_id: "run-A"}]
}')"
_mc_old_comment_body="$(cat <<EOF_OLD_COMMENT
### Automated Reviewer Loop Summary

*Posted automatically by \`pr-review-loop.sh\`.*

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_mc_stale_available_payload" | jq '.')
\`\`\`
EOF_OLD_COMMENT
)"
_mc_new_comment_body="$(cat <<'EOF_NEW_COMMENT'
### Automated Reviewer Loop Summary

*Posted automatically by `pr-review-loop.sh`.*

<!-- reviewer-loop-history:v1 -->
```json
{"schema":"reviewer_loop_history.v1","history_status":"unavailable","history_unavailable_reason":"comment_read_failed","entries":[]}
```
EOF_NEW_COMMENT
)"
_mc_two_comment_json="$(jq -n \
  --arg oldBody "$_mc_old_comment_body" \
  --arg newBody "$_mc_new_comment_body" \
  '[
    {id: 10, created_at: "2026-08-19T00:00:00Z", body: $oldBody},
    {id: 11, created_at: "2026-08-19T01:00:00Z", body: $newBody}
  ]')"
export MOCK_GH_COMMENTS_OUTPUT="$_mc_two_comment_json"
run_test "cycles_resolve_counts_newest_unavailable_fails_closed_not_stale" "-1 -1" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-A" 2>/dev/null)"
run_test "cycles_end_to_end_newest_unavailable_escalates" "yes" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-A" 2>/dev/null)
  reviewer_loop_cycle_count_unavailable_should_escalate "$_lc" needs_fixes && echo yes || echo no
)"
unset MOCK_GH_COMMENTS_OUTPUT
unset _mc_stale_available_payload _mc_old_comment_body
unset _mc_new_comment_body _mc_two_comment_json

# 10 prior fixer-dispatch entries under run_id "run-A" → resolving with
# run_id "run-A" yields lifetime=10 run=10, matching the default per-run
# cap of 10.
_mc_ten_dispatch_comment_json="$(jq -n --arg body "$_mc_ten_dispatch_body" \
  '[{id: 1, created_at: "2026-08-18T00:00:00Z",
     body: ("### Automated Reviewer Loop Summary\n\n*Posted automatically by `pr-review-loop.sh`.*\n\n" + $body)}]')"
export MOCK_GH_COMMENTS_OUTPUT="$_mc_ten_dispatch_comment_json"
run_test "cycles_resolve_counts_ten_prior_same_run_is_ten_ten" "10 10" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-A" 2>/dev/null)"
# AC: end-to-end — the per-run count against the default cap (10) with a
# needs_fixes verdict must trip max_cycles_exceeded when queried with the
# SAME run_id the entries were recorded under.
run_test "cycles_end_to_end_same_run_reaches_per_run_cap_escalates" "yes" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-A" 2>/dev/null)
  _mx="$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
  reviewer_loop_cap_exceeded "$_rc" "$_mx" needs_fixes && echo yes || echo no
)"

# AC: "per-run reset across a run boundary" — the SAME 10-entry ledger,
# queried with a NEW run_id ("run-B"), must NOT trip the per-run cap
# (fresh run boundary, 0 per-run cycles so far), even though the lifetime
# count (10) is unchanged and would already be visible to the lifetime
# ceiling check.
run_test "cycles_end_to_end_new_run_boundary_does_not_trip_per_run_cap" "no" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-B" 2>/dev/null)
  _mx="$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
  reviewer_loop_cap_exceeded "$_rc" "$_mx" needs_fixes && echo yes || echo no
)"
run_test "cycles_end_to_end_new_run_boundary_lifetime_still_visible" "10" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-B" 2>/dev/null)
  echo "$_lc"
)"
unset MOCK_GH_COMMENTS_OUTPUT

# AC: "lifetime ceiling tripping when no single run reached 10" — three
# separate runs of 9 dispatches each (27 distinct-head-sha entries total,
# each run individually under the per-run cap of 10), queried with a
# brand-new fourth run_id. The per-run count is 0 (new run boundary) and
# does NOT trip max_cycles; the lifetime count is 27, which DOES trip
# max_total_cycles (default 25) — proving the lifetime ceiling catches
# exactly the case a per-run-only cap would miss.
_mc_three_runs_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: (
    [range(1;10) | {iteration: ., head_sha: ("r1-" + (.|tostring)), result: "needs_fixes", run_id: "run-1"}] +
    [range(1;10) | {iteration: ., head_sha: ("r2-" + (.|tostring)), result: "needs_fixes", run_id: "run-2"}] +
    [range(1;10) | {iteration: ., head_sha: ("r3-" + (.|tostring)), result: "needs_fixes", run_id: "run-3"}]
  )
}')"
_mc_three_runs_comment_json="$(jq -n --arg body "$(printf '### Automated Reviewer Loop Summary\n\n*Posted automatically by `pr-review-loop.sh`.*\n\n<!-- reviewer-loop-history:v1 -->\n```json\n%s\n```\n' "$(printf '%s\n' "$_mc_three_runs_payload" | jq '.')")" \
  '[{id: 5, created_at: "2026-08-19T00:00:00Z", body: $body}]')"
export MOCK_GH_COMMENTS_OUTPUT="$_mc_three_runs_comment_json"
run_test "cycles_multi_run_resolve_counts" "27 0" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-4" 2>/dev/null)"
run_test "cycles_multi_run_per_run_cap_not_tripped" "no" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-4" 2>/dev/null)
  _mx="$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
  reviewer_loop_cap_exceeded "$_rc" "$_mx" needs_fixes && echo yes || echo no
)"
run_test "cycles_multi_run_lifetime_ceiling_tripped" "yes" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-4" 2>/dev/null)
  _mtx="$(reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
  reviewer_loop_cap_exceeded "$_lc" "$_mtx" needs_fixes && echo yes || echo no
)"
# AC: "both reasons being distinguishable in output" — the main flow must
# assign two DISTINCT literal REASON strings for the two outcomes (guards
# against a future edit accidentally reusing one string for both, which
# would make the two escalation causes indistinguishable to an operator).
run_test "cycles_reasons_max_cycles_exceeded_present_in_source" "1"   "$(grep -c 'aggregate_reason="max_cycles_exceeded"' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
run_test "cycles_reasons_max_total_cycles_exceeded_present_in_source" "1"   "$(grep -c 'aggregate_reason="max_total_cycles_exceeded"' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
unset MOCK_GH_COMMENTS_OUTPUT

# 3 prior fixer-dispatch entries → both counts 3, well under either
# default cap (10 / 25) → neither is exceeded.
_mc_three_dispatch_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [range(1;4) | {iteration: ., head_sha: ("sha-" + (.|tostring)), result: "needs_fixes", run_id: "run-C"}]
}')"
_mc_three_dispatch_comment_json="$(jq -n --arg body "$(printf '%s\n' "$_mc_three_dispatch_payload" | jq '.')" \
  '[{id: 2, created_at: "2026-08-18T00:00:00Z",
     body: ("### Automated Reviewer Loop Summary\n\n*Posted automatically by `pr-review-loop.sh`.*\n\n<!-- reviewer-loop-history:v1 -->\n```json\n" + $body + "\n```")}]')"
export MOCK_GH_COMMENTS_OUTPUT="$_mc_three_dispatch_comment_json"
run_test "cycles_resolve_counts_three_prior_same_run_is_three_three" "3 3" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-C" 2>/dev/null)"
run_test "cycles_end_to_end_under_both_caps_does_not_escalate" "no no" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-C" 2>/dev/null)
  _mx="$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
  _mtx="$(reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
  _per_run="no"; _lifetime="no"
  reviewer_loop_cap_exceeded "$_rc" "$_mx" needs_fixes && _per_run="yes"
  reviewer_loop_cap_exceeded "$_lc" "$_mtx" needs_fixes && _lifetime="yes"
  echo "$_per_run $_lifetime"
)"
unset MOCK_GH_COMMENTS_OUTPUT

# AC: "back-compat entries lacking a run id" (end-to-end via mocked gh) —
# entries with no run_id (as recorded by the pre-dual-cap script version,
# e.g. PR #1507's own cycles 1-5) must not artificially reset OR inflate
# the per-run budget for a fresh run-id-aware invocation.
_mc_back_compat_comment_json="$(jq -n --arg body "$(printf '### Automated Reviewer Loop Summary\n\n*Posted automatically by `pr-review-loop.sh`.*\n\n<!-- reviewer-loop-history:v1 -->\n```json\n%s\n```\n' "$(printf '%s\n' "$_mc_back_compat_payload" | jq '.')")" \
  '[{id: 6, created_at: "2026-08-19T00:00:00Z", body: $body}]')"
export MOCK_GH_COMMENTS_OUTPUT="$_mc_back_compat_comment_json"
run_test "cycles_resolve_counts_back_compat_end_to_end" "5 0" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-fresh" 2>/dev/null)"
unset MOCK_GH_COMMENTS_OUTPUT

# API failure while resolving the ledger (after retries) → -1 -1
# (unavailable). CYCLE_LEDGER_RETRY_WAIT=0 avoids a real sleep between
# retry attempts in the test harness; CYCLE_LEDGER_MAX_RETRIES=1 keeps the
# retry count at its default so the retry path itself is exercised (2
# total attempts).
export MOCK_GH_COMMENTS_EXIT=1
export CYCLE_LEDGER_RETRY_WAIT=0
run_test "cycles_resolve_counts_api_failure_unavailable" "-1 -1" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-x" 2>/dev/null)"
run_test "cycles_resolve_counts_api_failure_retries_before_giving_up" "yes" "$(
  # Capture stderr into a variable first, then grep the variable — piping
  # directly into `grep -q` risks a SIGPIPE (exit 141) false-negative under
  # `set -o pipefail` if grep exits after its first match while the
  # function is still writing a later WARN line.
  _mc_retry_stderr="$(reviewer_loop_resolve_cycle_counts "42" "run-x" 2>&1 >/dev/null)"
  if printf '%s\n' "$_mc_retry_stderr" | grep -q "retrying"; then
    echo yes
  else
    echo no
  fi
)"
# reviewer_loop_cap_exceeded itself still fails open on an unknown (-1)
# count — it is strictly "is the known count at or past the cap"; the
# fail-closed behavior lives in reviewer_loop_cycle_count_unavailable_
# should_escalate (tested separately below), which the main flow checks
# first.
run_test "cycles_cap_check_still_fails_open_on_unknown_count" "no" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-x" 2>/dev/null)
  reviewer_loop_cap_exceeded "$_rc" 10 needs_fixes && echo yes || echo no
)"
unset MOCK_GH_COMMENTS_EXIT CYCLE_LEDGER_RETRY_WAIT

# --- reviewer_loop_cycle_count_unavailable_should_escalate ---
# Fail-closed safety check: an unreadable cycle ledger must not silently
# disable either cap backstop forever.

run_test "cycles_unavailable_escalates_on_needs_fixes" "yes" \
  "$(reviewer_loop_cycle_count_unavailable_should_escalate -1 needs_fixes && echo yes || echo no)"
run_test "cycles_unavailable_escalates_on_needs_rerun" "yes" \
  "$(reviewer_loop_cycle_count_unavailable_should_escalate -1 needs_rerun && echo yes || echo no)"
run_test "cycles_unavailable_does_not_escalate_on_clean" "no" \
  "$(reviewer_loop_cycle_count_unavailable_should_escalate -1 clean && echo yes || echo no)"
run_test "cycles_unavailable_does_not_escalate_on_already_escalate" "no" \
  "$(reviewer_loop_cycle_count_unavailable_should_escalate -1 escalate && echo yes || echo no)"
run_test "cycles_unavailable_does_not_fire_on_known_count" "no" \
  "$(reviewer_loop_cycle_count_unavailable_should_escalate 3 needs_fixes && echo yes || echo no)"
# AC / regression: end-to-end — an unreadable ledger on a PR with a
# needs_fixes verdict must escalate (fail closed), not silently retry forever.
export MOCK_GH_COMMENTS_EXIT=1
export CYCLE_LEDGER_RETRY_WAIT=0
run_test "cycles_end_to_end_unreadable_ledger_escalates" "yes" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-x" 2>/dev/null)
  reviewer_loop_cycle_count_unavailable_should_escalate "$_lc" needs_fixes && echo yes || echo no
)"
unset MOCK_GH_COMMENTS_EXIT CYCLE_LEDGER_RETRY_WAIT

# --- reviewer_loop_persist_failure_should_escalate ---
# Fail-closed safety check (Codex finding on PR #1507): if this cycle's own
# ledger entry could not be persisted, a dispatch-triggering result must
# not silently let the caller dispatch an uncounted fixer.

run_test "persist_failure_escalates_on_needs_fixes" "yes"   "$(reviewer_loop_persist_failure_should_escalate 1 needs_fixes && echo yes || echo no)"
run_test "persist_failure_escalates_on_needs_rerun" "yes"   "$(reviewer_loop_persist_failure_should_escalate 1 needs_rerun && echo yes || echo no)"
run_test "persist_failure_does_not_escalate_on_clean" "no"   "$(reviewer_loop_persist_failure_should_escalate 1 clean && echo yes || echo no)"
run_test "persist_failure_does_not_escalate_on_already_escalate" "no"   "$(reviewer_loop_persist_failure_should_escalate 1 escalate && echo yes || echo no)"
run_test "persist_failure_does_not_fire_when_persist_succeeded" "no"   "$(reviewer_loop_persist_failure_should_escalate 0 needs_fixes && echo yes || echo no)"

# --- reviewer_loop_history_build_entry writes run_id from the
#     current_run_id global (same convention already used in that function
#     for unresolved_thread_count/late_thread_count) ---

current_run_id="entry-write-test-run"
unresolved_thread_count=0
late_thread_count=0
pr_number=42
MOCK_GH_HEAD_SHA="entry-write-sha"
MOCK_GH_UPDATED_AT="2026-08-19T00:00:00Z"
export MOCK_GH_HEAD_SHA MOCK_GH_UPDATED_AT
_entry_write_payload="$(reviewer_loop_history_payload_from_existing "" "needs_fixes" "" "bugbot (needs_fixes)" "1" "0")"
run_test "cycles_build_entry_writes_run_id_from_global" "entry-write-test-run" \
  "$(printf '%s\n' "$_entry_write_payload" | jq -r '.entries[0].run_id')"
unset current_run_id unresolved_thread_count late_thread_count pr_number
unset MOCK_GH_HEAD_SHA MOCK_GH_UPDATED_AT

# --- reviewer_loop_history_current_head_sha fallback (Codex finding on
#     PR #1507): a failed/empty HEAD SHA lookup must never silently make an
#     entry uncountable (empty head_sha is excluded from both cap counts by
#     reviewer_loop_history_entries_count). A guaranteed-unique synthetic
#     placeholder keeps the entry countable instead. ---

pr_number=42
export MOCK_GH_EXIT=1
run_test "cycles_head_sha_fallback_on_lookup_failure_nonempty" "yes" "$(
  _hs="$(reviewer_loop_history_current_head_sha 2>/dev/null)"
  if [ -n "$_hs" ]; then echo yes; else echo no; fi
)"
run_test "cycles_head_sha_fallback_on_lookup_failure_has_prefix" "yes" "$(
  _hs="$(reviewer_loop_history_current_head_sha 2>/dev/null)"
  if [[ "$_hs" == unknown-* ]]; then echo yes; else echo no; fi
)"
run_test "cycles_head_sha_fallback_warns" "yes" "$(
  _stderr="$(reviewer_loop_history_current_head_sha 2>&1 >/dev/null)"
  if printf '%s
' "$_stderr" | grep -q "WARN.*could not resolve current HEAD SHA"; then
    echo yes
  else
    echo no
  fi
)"
unset MOCK_GH_EXIT

# AC: an entry written via the fallback path must be countable (non-empty
# head_sha), unlike the pre-fix behavior where an empty head_sha silently
# excluded the entry from both cap counts.
# shellcheck disable=SC2034 # read via "${current_run_id:-}" inside
# reviewer_loop_history_build_entry (pr-review-loop.sh), which ShellCheck
# cannot trace across the dynamic HARNESS_MODE=1 source above.
current_run_id="head-sha-fallback-run"
# shellcheck disable=SC2034 # same as current_run_id above.
unresolved_thread_count=0
# shellcheck disable=SC2034 # same as current_run_id above.
late_thread_count=0
export MOCK_GH_EXIT=1
_fallback_entry_payload="$(reviewer_loop_history_payload_from_existing "" "needs_fixes" "" "bugbot (needs_fixes)" "1" "0")"
run_test "cycles_head_sha_fallback_entry_has_nonempty_head_sha" "yes" "$(
  _entry_hs="$(printf '%s
' "$_fallback_entry_payload" | jq -r '.entries[0].head_sha')"
  if [ -n "$_entry_hs" ]; then echo yes; else echo no; fi
)"
unset MOCK_GH_EXIT current_run_id unresolved_thread_count late_thread_count pr_number
unset _fallback_entry_payload

# --- Regression guard (Codex finding on PR #1507): the max_cycles cap
# override in the main flow MUST run before the compare-mode metrics-row
# append. --compare mode's own contract is "the overall exit code and
# RESULT are identical to what normal mode would produce" — the overrides
# are unconditional (they also apply in --compare mode), so if the metrics
# row were appended first, docs/workflow/retro-metrics-platforms.md would
# record a stale pre-cap value while the script's own final RESULT/summary
# say escalate, corrupting reviewer-graduation comparison data. This is a
# source-ordering check (the runtime behavior requires a full --compare-
# mode platform run to exercise, which is out of scope for this harness)
# but it directly guards against the exact regression found.
_mc_cap_line="$(grep -n 'reviewer_loop_cap_exceeded "\$cycle_count" "\$max_cycles" "\$aggregate_result"' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
_mc_metrics_line="$(grep -n 'append_compare_metrics_row "\${_metrics_args\[@\]}"' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
if [ -n "$_mc_cap_line" ] && [ -n "$_mc_metrics_line" ] \
    && [ "$_mc_cap_line" -lt "$_mc_metrics_line" ]; then
  run_test "cycles_cap_override_precedes_compare_metrics_append" "yes" "yes"
else
  run_test "cycles_cap_override_precedes_compare_metrics_append" "yes" "no"
fi
unset _mc_cap_line _mc_metrics_line

# --- Single-RESULT-line fix (Codex finding on PR #1507: "emit only the
#     corrected reviewer-loop result") ---
#
# The script's own kv_value helper (used elsewhere in this same script to
# parse a sub-invocation's key=value output) returns the FIRST matching
# key, not the last (`{ ...; print; exit }` on first match) — so printing
# RESULT= twice (an initial value, then a "corrected" one after a
# persistence failure) would be silently invisible to any caller using
# that same convention, which would still see the stale first value despite
# the script exiting escalated. The fix restructures the tail of the main
# flow so _post_review_summary (and its ledger_persist_failed correction)
# runs BEFORE the single RESULT=/REASON= print, not after — replacing the
# earlier "supplementary corrected compare-metrics row" workaround (now
# unnecessary: the main compare-metrics append also moved after
# persistence, so it always reflects the single final result too).
#
# This is a source-ordering check (the runtime behavior requires a full
# needs_fixes-with-persistence-failure platform run to exercise end to end,
# which is out of scope for this harness) but it directly guards against
# the exact regression found: _post_review_summary's call site must appear
# BEFORE print_kv RESULT "$aggregate_result" in the tail of the script.
_post_summary_call_line="$(grep -n '_post_review_summary "\$aggregate_result" "\$aggregate_reason"'   "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null   | head -1 | cut -d: -f1)"
_print_result_line="$(grep -n 'print_kv RESULT "\$aggregate_result"'   "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null   | head -1 | cut -d: -f1)"
if [ -n "$_post_summary_call_line" ] && [ -n "$_print_result_line" ]     && [ "$_post_summary_call_line" -lt "$_print_result_line" ]; then
  run_test "persist_and_correction_precede_single_result_print" "yes" "yes"
else
  run_test "persist_and_correction_precede_single_result_print" "yes" "no"
fi
# Only ONE call site for `print_kv RESULT "$aggregate_result"` should exist
# in the whole script — a second, differently-worded RESULT print (e.g.
# `print_kv RESULT escalate`) reintroducing the two-line bug would not be
# caught by the check above alone.
run_test "only_one_print_kv_result_aggregate_result_call_site" "1"   "$(grep -c 'print_kv RESULT "\$aggregate_result"' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
unset _post_summary_call_line _print_result_line

# Function-ordering check (mirrors Area 11's Test 11.6) — the max_cycles /
# max_total_cycles enforcement functions must stay callable from the
# harness after future refactors move code around.
for _mc_fn in reviewer_loop_resolve_run_id reviewer_loop_history_entries_count \
    reviewer_loop_history_select_latest_summary_record \
    reviewer_loop_resolve_max_cycles reviewer_loop_resolve_max_total_cycles \
    reviewer_loop_cap_exceeded reviewer_loop_cycle_count_unavailable_should_escalate \
    reviewer_loop_persist_failure_should_escalate \
    reviewer_loop_history_current_head_sha \
    reviewer_loop_resolve_cycle_counts; do
  _mc_fn_line="$(grep -n "^${_mc_fn}()" \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
    | head -1 | cut -d: -f1)"
  _mc_harness_return_line="$(grep -n '_HARNESS_MODE_EFFECTIVE.*return 0' \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
    | head -1 | cut -d: -f1)"
  if [ -n "$_mc_fn_line" ] && [ -n "$_mc_harness_return_line" ] \
      && [ "$_mc_fn_line" -lt "$_mc_harness_return_line" ]; then
    run_test "cycles_fn_defined_before_harness_return_${_mc_fn}" "yes" "yes"
  else
    run_test "cycles_fn_defined_before_harness_return_${_mc_fn}" "yes" "no"
  fi
done
unset _mc_fn _mc_fn_line _mc_harness_return_line

unset _mc_no_marker_body _mc_marker_no_json_body
unset _mc_ten_dispatch_payload _mc_ten_dispatch_body _mc_ten_dispatch_comment_json
unset _mc_mixed_result_payload _mc_mixed_result_body
unset _mc_dup_head_sha_payload _mc_dup_head_sha_body
unset _mc_rerun_then_fixes_payload _mc_rerun_then_fixes_body
unset _mc_empty_head_sha_payload _mc_empty_head_sha_body
unset _mc_back_compat_payload _mc_back_compat_body _mc_back_compat_comment_json
unset _mc_persisted_unavailable_body _mc_malformed_body _mc_wrong_schema_body
unset _mc_three_dispatch_payload _mc_three_dispatch_comment_json
unset _mc_three_runs_payload _mc_three_runs_comment_json
unset _entry_write_payload

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
# Area 12b: ready-phase gate distinguishes GitHub API rate-limit exhaustion
# from a genuine review-gate failure (issue #1509)
#
# gh_rate_limit_exhausted_reset() and ensure_pr_ready_for_ready_phase() are
# defined before the HARNESS_MODE return point and are therefore callable
# directly from the test harness.
#
# Uses the strict-mock pattern established for issue #1531 (a PATH-installed
# `gh` script that enumerates every invocation the code under test legitimately
# makes and hard-errors on anything else) rather than the permissive global
# MOCK_GH_* fallback used elsewhere in this file — a renamed or dropped
# `gh api rate_limit` call must fail the test, not silently return an empty
# default that happens to still satisfy the assertion.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 12b: rate-limit-aware ready-phase gate (issue #1509) ==="

_1509_mkmock() {
  # $1 = mock dir, $2 = case body (bash `case "$*" in ... esac` arms)
  if [ "$#" -ne 2 ]; then
    echo "ERROR: _1509_mkmock requires exactly 2 arguments (dir, arms), got $#" >&2
    return 1
  fi
  local dir="$1"
  local arms="$2"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    echo "ERROR: _1509_mkmock: '$dir' is not a valid directory" >&2
    return 1
  fi
  if ! cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\$RL1509_CALL_LOG"
case "\$*" in
$arms
  *)
    printf 'UNEXPECTED gh invocation in 1509 mock: %s\n' "\$*" >&2
    exit 1
    ;;
esac
EOF
  then
    echo "ERROR: _1509_mkmock: failed to write $dir/gh" >&2
    return 1
  fi
  if ! chmod +x "$dir/gh"; then
    echo "ERROR: _1509_mkmock: failed to chmod +x $dir/gh" >&2
    return 1
  fi
}

# --- gh_rate_limit_exhausted_reset: core exhausted -------------------------
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":0,"reset":1700000100},"graphql":{"limit":5000,"remaining":5000,"reset":1700009999}}}\n'"'"'
    exit 0 ;;'
_1509_out="$(PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" gh_rate_limit_exhausted_reset)"
_1509_rc=$?
run_test "rl1509_core_exhausted_prints_reset" "1700000100" "$_1509_out"
run_test "rl1509_core_exhausted_exit_0" "0" "$_1509_rc"
run_test "rl1509_core_exhausted_probed_rate_limit" "yes" \
  "$([ "$(grep -c -- 'api rate_limit' "$_1509_log" 2>/dev/null || true)" -ge 1 ] && echo yes || echo no)"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_out _1509_rc

# --- gh_rate_limit_exhausted_reset: graphql exhausted -----------------------
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":5000,"reset":1700009999},"graphql":{"limit":5000,"remaining":0,"reset":1700000200}}}\n'"'"'
    exit 0 ;;'
_1509_out="$(PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" gh_rate_limit_exhausted_reset)"
run_test "rl1509_graphql_exhausted_prints_reset" "1700000200" "$_1509_out"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_out

# --- gh_rate_limit_exhausted_reset: both exhausted -> earliest reset wins --
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":0,"reset":1700000500},"graphql":{"limit":5000,"remaining":0,"reset":1700000300}}}\n'"'"'
    exit 0 ;;'
_1509_out="$(PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" gh_rate_limit_exhausted_reset)"
run_test "rl1509_both_exhausted_earliest_reset" "1700000300" "$_1509_out"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_out

# --- gh_rate_limit_exhausted_reset: neither exhausted -> empty, exit 1 -----
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":4999,"reset":1700009999},"graphql":{"limit":5000,"remaining":5000,"reset":1700009999}}}\n'"'"'
    exit 0 ;;'
set +e
_1509_out="$(PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" gh_rate_limit_exhausted_reset)"
_1509_rc=$?
set -e
run_test "rl1509_not_exhausted_empty_output" "" "$_1509_out"
run_test "rl1509_not_exhausted_exit_1" "1" "$_1509_rc"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_out _1509_rc

# --- gh_rate_limit_exhausted_reset: probe call itself fails -> exit 1 ------
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "api rate_limit")
    exit 1 ;;'
set +e
_1509_out="$(PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" gh_rate_limit_exhausted_reset)"
_1509_rc=$?
set -e
run_test "rl1509_probe_failure_empty_output" "" "$_1509_out"
run_test "rl1509_probe_failure_exit_1" "1" "$_1509_rc"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_out _1509_rc

# --- gh_rate_limit_exhausted_reset: malformed JSON does not abort the caller
# under `set -e` (regression guard for the unguarded-assignment failure mode) --
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "api rate_limit")
    printf '"'"'not-json\n'"'"'
    exit 0 ;;'
set +e
_1509_out="$(PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" gh_rate_limit_exhausted_reset)"
_1509_rc=$?
set -e
run_test "rl1509_malformed_json_empty_output" "" "$_1509_out"
run_test "rl1509_malformed_json_exit_1" "1" "$_1509_rc"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_out _1509_rc

# --- ensure_pr_ready_for_ready_phase: gh pr view failure + confirmed rate
# limit exhaustion -> exit 3, distinct from the generic exit 2, and
# READY_PHASE_GATE_RATE_LIMIT_RESET carries the reset timestamp -------------
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "pr view 999 --json isDraft --jq .isDraft")
    exit 1 ;;
  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":0,"reset":1700000777},"graphql":{"limit":5000,"remaining":5000,"reset":1700009999}}}\n'"'"'
    exit 0 ;;'
set +e
PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" \
  ensure_pr_ready_for_ready_phase "999" >/dev/null 2>&1
_1509_rc=$?
set -e
run_test "rl1509_gate_draft_state_rate_limited_exit_3" "3" "$_1509_rc"
run_test "rl1509_gate_draft_state_rate_limited_reset_captured" "1700000777" \
  "$READY_PHASE_GATE_RATE_LIMIT_RESET"
run_test "rl1509_gate_draft_state_rate_limited_probed" "yes" \
  "$([ "$(grep -c -- 'api rate_limit' "$_1509_log" 2>/dev/null || true)" -ge 1 ] && echo yes || echo no)"
run_test "rl1509_gate_draft_state_rate_limited_did_not_call_pr_ready" "0" \
  "$(grep -c -- 'pr ready 999' "$_1509_log" 2>/dev/null || true)"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_rc

# --- ensure_pr_ready_for_ready_phase: gh pr view failure WITHOUT confirmed
# rate-limit exhaustion still returns the original exit 2 (unchanged
# behavior — an unexplained failure is not asserted to be a rate limit) -----
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "pr view 999 --json isDraft --jq .isDraft")
    exit 1 ;;
  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":4999,"reset":1700009999},"graphql":{"limit":5000,"remaining":5000,"reset":1700009999}}}\n'"'"'
    exit 0 ;;'
READY_PHASE_GATE_RATE_LIMIT_RESET="stale-from-prior-cycle"
set +e
PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" \
  ensure_pr_ready_for_ready_phase "999" >/dev/null 2>&1
_1509_rc=$?
set -e
run_test "rl1509_gate_draft_state_unexplained_failure_exit_2" "2" "$_1509_rc"
run_test "rl1509_gate_unexplained_failure_clears_stale_reset" "" \
  "$READY_PHASE_GATE_RATE_LIMIT_RESET"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_rc

# --- ensure_pr_ready_for_ready_phase: `gh pr ready` failure (after a
# successful draft-state read) + confirmed rate-limit exhaustion -> exit 3 --
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "pr view 999 --json isDraft --jq .isDraft")
    printf '"'"'true\n'"'"'
    exit 0 ;;
  "pr ready 999")
    exit 1 ;;
  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":0,"reset":1700000888},"graphql":{"limit":5000,"remaining":5000,"reset":1700009999}}}\n'"'"'
    exit 0 ;;'
set +e
PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" \
  ensure_pr_ready_for_ready_phase "999" >/dev/null 2>&1
_1509_rc=$?
set -e
run_test "rl1509_gate_pr_ready_rate_limited_exit_3" "3" "$_1509_rc"
run_test "rl1509_gate_pr_ready_rate_limited_reset_captured" "1700000888" \
  "$READY_PHASE_GATE_RATE_LIMIT_RESET"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_rc
unset -f _1509_mkmock
READY_PHASE_GATE_RATE_LIMIT_RESET=""

# --- reviewer_failed_label_required_for_result: rate_limited escalation is
# infrastructure unavailability, not a review verdict — no label -----------
#
# Defined locally (not reusing Area 12's _reviewer_failed_required) because
# Area 12 ends by `unset`-ing that name — with neither -f nor -v given, bash
# falls back to unsetting the FUNCTION when no variable by that name exists,
# so the Area 12 helper is gone by the time this block runs.
_1509_reviewer_failed_required() {
  if reviewer_failed_label_required_for_result "$1" "${2:-}"; then
    printf 'yes'
  else
    printf 'no'
  fi
}
run_test "reviewer_failed_escalate_rate_limited_no_label" "no" \
  "$(_1509_reviewer_failed_required escalate rate_limited)"
# Sibling REASON tokens must be unaffected by the new exception (regression
# guard against an over-broad case match swallowing other escalate reasons).
run_test "reviewer_failed_escalate_ready_for_review_failed_still_label" "yes" \
  "$(_1509_reviewer_failed_required escalate ready_for_review_failed)"
unset -f _1509_reviewer_failed_required

# ---------------------------------------------------------------------------
# Area 13: PR #801 follow-up coverage for reviewer-loop failure paths
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 13: PR #801 reviewer-loop failure paths ==="

export MOCK_GH_OUTPUT='{
  "reviewThreads": {
  "pageInfo": {"hasNextPage": false, "endCursor": null},
  "nodes": [
    {
      "id": "thread-outdated",
      "isResolved": false,
      "isOutdated": true,
      "firstComment": {
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
      "firstComment": {
        "nodes": [
          {
            "author": {"login": "chatgpt-codex-connector"},
            "body": "active Codex finding"
          }
        ]
      }
    }
  ]
  }
}'
run_test "codex_thread_audit_ignores_outdated" "1" \
  "$(check_unresolved_threads "42" "owner/repo" strict "chatgpt-codex-connector")"
export MOCK_GH_OUTPUT='{
  "reviewThreads": {
  "pageInfo": {"hasNextPage": false, "endCursor": null},
  "nodes": [
    {
      "id": "thread-outdated",
      "isResolved": false,
      "isOutdated": true,
      "firstComment": {
        "nodes": [
          {
            "author": {"login": "chatgpt-codex-connector"},
            "body": "stale Codex finding"
          }
        ]
      }
    }
  ]
  }
}'
run_test "codex_thread_audit_all_outdated_clean" "0" \
  "$(check_unresolved_threads "42" "owner/repo" strict "chatgpt-codex-connector")"
unset MOCK_GH_OUTPUT

manual_readiness_audit_count() {
  jq --arg codex_bot "chatgpt-codex-connector" '[.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | select((.isOutdated // false) == false)
        | select(.comments.nodes[0].author.login as $a | ["coderabbitai","devin-ai-integration","greptile-apps",$codex_bot] | index($a) != null)
        | select((.comments.nodes[0].body // "") | test("✅ Addressed") | not)] | length'
}

_manual_audit_fixture='{
  "data": {
    "repository": {
      "pullRequest": {
        "reviewThreads": {
          "nodes": [
            {
              "id": "active-codex",
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
            },
            {
              "id": "outdated-codex",
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
              "id": "addressed-coderabbit",
              "isResolved": false,
              "isOutdated": false,
              "comments": {
                "nodes": [
                  {
                    "author": {"login": "coderabbitai"},
                    "body": "✅ Addressed in latest commit"
                  }
                ]
              }
            }
          ]
        }
      }
    }
  }
}'
run_test "manual_readiness_audit_active_codex_blocks" "1" \
  "$(printf '%s\n' "$_manual_audit_fixture" | manual_readiness_audit_count)"

_manual_audit_fixture_outdated_only='{
  "data": {
    "repository": {
      "pullRequest": {
        "reviewThreads": {
          "nodes": [
            {
              "id": "outdated-codex",
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
        }
      }
    }
  }
}'
run_test "manual_readiness_audit_outdated_codex_passes" "0" \
  "$(printf '%s\n' "$_manual_audit_fixture_outdated_only" | manual_readiness_audit_count)"

_docs_is_outdated_field_count="$(grep -h 'nodes { isResolved isOutdated comments(first: 1)' \
  "$REPO_ROOT/docs/workflow/development-workflow/protocols/03-implement-development-protocol.md" \
  "$REPO_ROOT/docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
  | wc -l | tr -d ' ')"
run_test "manual_readiness_audit_docs_request_is_outdated" "5" "$_docs_is_outdated_field_count"

_docs_is_outdated_filter_count="$(grep -h 'select((.isOutdated // false) == false)' \
  "$REPO_ROOT/docs/workflow/development-workflow/protocols/03-implement-development-protocol.md" \
  "$REPO_ROOT/docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
  | wc -l | tr -d ' ')"
run_test "manual_readiness_audit_docs_filter_outdated" "5" "$_docs_is_outdated_filter_count"
unset _manual_audit_fixture _manual_audit_fixture_outdated_only _docs_is_outdated_field_count _docs_is_outdated_filter_count

if grep -q "Codex acknowledgement detected; waiting for current-head review or inline review comments" \
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
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
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
run_test "codex_usage_limit_comment_verdict" \
  "VERDICT: UNAVAILABLE — Codex GitHub review usage limit reached" \
  "$(printf '%s\n' "$_codex_usage_comment_output" | grep "^VERDICT:")"
run_test "codex_usage_limit_comment_reason" "REASON=codex-github-usage-limit" \
  "$(printf '%s\n' "$_codex_usage_comment_output" | grep "^REASON=")"
run_test "codex_usage_limit_comment_comment_count" "COMMENT_COUNT=0" \
  "$(printf '%s\n' "$_codex_usage_comment_output" | grep "^COMMENT_COUNT=")"
run_test "codex_usage_limit_comment_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$_codex_usage_comment_output" | grep "^BLOCKING_COUNT=")"
run_test "codex_usage_limit_comment_suggestion_count" "SUGGESTION_COUNT=0" \
  "$(printf '%s\n' "$_codex_usage_comment_output" | grep "^SUGGESTION_COUNT=")"
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
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"abcreview1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex review capacity exhausted. Please rerun after quota reset."}]\n'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
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
run_test "codex_usage_limit_review_verdict" \
  "VERDICT: UNAVAILABLE — Codex GitHub review usage limit reached" \
  "$(printf '%s\n' "$_codex_usage_review_output" | grep "^VERDICT:")"
run_test "codex_usage_limit_review_reason" "REASON=codex-github-usage-limit" \
  "$(printf '%s\n' "$_codex_usage_review_output" | grep "^REASON=")"
run_test "codex_usage_limit_review_comment_count" "COMMENT_COUNT=0" \
  "$(printf '%s\n' "$_codex_usage_review_output" | grep "^COMMENT_COUNT=")"
run_test "codex_usage_limit_review_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$_codex_usage_review_output" | grep "^BLOCKING_COUNT=")"
run_test "codex_usage_limit_review_suggestion_count" "SUGGESTION_COUNT=0" \
  "$(printf '%s\n' "$_codex_usage_review_output" | grep "^SUGGESTION_COUNT=")"
rm -rf "$_codex_usage_review_mock_dir"
unset _codex_usage_review_mock_dir _codex_usage_review_output _codex_usage_review_exit

_codex_reaction_mock_dir="$(mktemp -d)"
cat > "$_codex_reaction_mock_dir/gh" <<'CODEX_REACTION_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcreact1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":103,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_REACTION_GH
chmod +x "$_codex_reaction_mock_dir/gh"

_codex_reaction_output=""
_codex_reaction_exit=0
PATH="$_codex_reaction_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_reaction_mock_dir/output.txt" 2>&1 || _codex_reaction_exit=$?
_codex_reaction_output="$(cat "$_codex_reaction_mock_dir/output.txt")"
run_test "codex_reaction_only_exit_unavailable" "2" "$_codex_reaction_exit"
run_test "codex_reaction_only_reason" "REASON=codex-github-reaction-without-review" \
  "$(printf '%s\n' "$_codex_reaction_output" | grep "^REASON=")"
rm -rf "$_codex_reaction_mock_dir"
unset _codex_reaction_mock_dir _codex_reaction_output _codex_reaction_exit

_codex_clean_root_review_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_clean_root_review_comment_mock_dir/gh" <<'CODEX_CLEAN_ROOT_REVIEW_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcdefab1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":118,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:218,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `abcdefab12` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_CLEAN_ROOT_REVIEW_COMMENT_GH
chmod +x "$_codex_clean_root_review_comment_mock_dir/gh"

_codex_clean_root_review_comment_output=""
_codex_clean_root_review_comment_exit=0
PATH="$_codex_clean_root_review_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_clean_root_review_comment_mock_dir/output.txt" 2>&1 || _codex_clean_root_review_comment_exit=$?
_codex_clean_root_review_comment_output="$(cat "$_codex_clean_root_review_comment_mock_dir/output.txt")"
run_test "codex_clean_root_review_comment_exit_clean" "0" "$_codex_clean_root_review_comment_exit"
run_test "codex_clean_root_review_comment_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_clean_root_review_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_clean_root_review_comment_mock_dir"
unset _codex_clean_root_review_comment_mock_dir _codex_clean_root_review_comment_output _codex_clean_root_review_comment_exit

_codex_full_root_review_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_full_root_review_comment_mock_dir/gh" <<'CODEX_FULL_ROOT_REVIEW_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcabcabcabc1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":126,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:226,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `abcabcabcabc1234567890` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_FULL_ROOT_REVIEW_COMMENT_GH
chmod +x "$_codex_full_root_review_comment_mock_dir/gh"

_codex_full_root_review_comment_output=""
_codex_full_root_review_comment_exit=0
PATH="$_codex_full_root_review_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_full_root_review_comment_mock_dir/output.txt" 2>&1 || _codex_full_root_review_comment_exit=$?
_codex_full_root_review_comment_output="$(cat "$_codex_full_root_review_comment_mock_dir/output.txt")"
run_test "codex_full_root_review_comment_exit_clean" "0" "$_codex_full_root_review_comment_exit"
run_test "codex_full_root_review_comment_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_full_root_review_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_full_root_review_comment_mock_dir"
unset _codex_full_root_review_comment_mock_dir _codex_full_root_review_comment_output _codex_full_root_review_comment_exit

_codex_stale_root_review_comment_mock_dir="$(mktemp -d)"
cat > "$_codex_stale_root_review_comment_mock_dir/gh" <<'CODEX_STALE_ROOT_REVIEW_COMMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abc123aa1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":119,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":219,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `def456bb12`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_STALE_ROOT_REVIEW_COMMENT_GH
chmod +x "$_codex_stale_root_review_comment_mock_dir/gh"

_codex_stale_root_review_comment_output=""
_codex_stale_root_review_comment_exit=0
PATH="$_codex_stale_root_review_comment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_stale_root_review_comment_mock_dir/output.txt" 2>&1 || _codex_stale_root_review_comment_exit=$?
_codex_stale_root_review_comment_output="$(cat "$_codex_stale_root_review_comment_mock_dir/output.txt")"
run_test "codex_stale_root_review_comment_exit_unavailable" "2" "$_codex_stale_root_review_comment_exit"
if printf '%s\n' "$_codex_stale_root_review_comment_output" | grep -q "^VERDICT: APPROVED"; then
  _codex_stale_root_review_comment_approved="yes"
else
  _codex_stale_root_review_comment_approved="no"
fi
run_test "codex_stale_root_review_comment_not_approved" "no" "$_codex_stale_root_review_comment_approved"
rm -rf "$_codex_stale_root_review_comment_mock_dir"
unset _codex_stale_root_review_comment_mock_dir _codex_stale_root_review_comment_output _codex_stale_root_review_comment_exit _codex_stale_root_review_comment_approved

_codex_newer_root_blocks_old_review_mock_dir="$(mktemp -d)"
cat > "$_codex_newer_root_blocks_old_review_mock_dir/gh" <<'CODEX_NEWER_ROOT_BLOCKS_OLD_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'feed12341234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":123,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"feed12341234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":223,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: newer root finding.\\n\\n**Reviewed commit:** `feed1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_NEWER_ROOT_BLOCKS_OLD_REVIEW_GH
chmod +x "$_codex_newer_root_blocks_old_review_mock_dir/gh"

_codex_newer_root_blocks_old_review_output=""
_codex_newer_root_blocks_old_review_exit=0
PATH="$_codex_newer_root_blocks_old_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_newer_root_blocks_old_review_mock_dir/output.txt" 2>&1 || _codex_newer_root_blocks_old_review_exit=$?
_codex_newer_root_blocks_old_review_output="$(cat "$_codex_newer_root_blocks_old_review_mock_dir/output.txt")"
run_test "codex_newer_root_blocks_old_review_exit_needs_revision" "1" "$_codex_newer_root_blocks_old_review_exit"
run_test "codex_newer_root_blocks_old_review_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_newer_root_blocks_old_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_newer_root_blocks_old_review_mock_dir"
unset _codex_newer_root_blocks_old_review_mock_dir _codex_newer_root_blocks_old_review_output _codex_newer_root_blocks_old_review_exit

_codex_tied_root_blocks_review_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_root_blocks_review_mock_dir/gh" <<'CODEX_TIED_ROOT_BLOCKS_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'cafe12341234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":127,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"cafe12341234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":227,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: tied root finding.\\n\\n**Reviewed commit:** `cafe1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_ROOT_BLOCKS_REVIEW_GH
chmod +x "$_codex_tied_root_blocks_review_mock_dir/gh"

_codex_tied_root_blocks_review_output=""
_codex_tied_root_blocks_review_exit=0
PATH="$_codex_tied_root_blocks_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_root_blocks_review_mock_dir/output.txt" 2>&1 || _codex_tied_root_blocks_review_exit=$?
_codex_tied_root_blocks_review_output="$(cat "$_codex_tied_root_blocks_review_mock_dir/output.txt")"
run_test "codex_tied_root_blocks_review_exit_needs_revision" "1" "$_codex_tied_root_blocks_review_exit"
run_test "codex_tied_root_blocks_review_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_tied_root_blocks_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_root_blocks_review_mock_dir"
unset _codex_tied_root_blocks_review_mock_dir _codex_tied_root_blocks_review_output _codex_tied_root_blocks_review_exit

# Reverse of codex_tied_root_blocks_review: this time the SHA-pinned root
# comment is CLEAN and the submitted review (same timestamp) is BLOCKING. The
# tie-break must be symmetric (blocking wins on ties regardless of which
# source supplied it), so this must also resolve to NEEDS_REVISION.
_codex_tied_review_blocks_root_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_review_blocks_root_mock_dir/gh" <<'CODEX_TIED_REVIEW_BLOCKS_ROOT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'beefcafe1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":129,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"beefcafe1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: tied review finding."}]\n'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":229,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `beefcafe1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_REVIEW_BLOCKS_ROOT_GH
chmod +x "$_codex_tied_review_blocks_root_mock_dir/gh"

_codex_tied_review_blocks_root_output=""
_codex_tied_review_blocks_root_exit=0
PATH="$_codex_tied_review_blocks_root_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_review_blocks_root_mock_dir/output.txt" 2>&1 || _codex_tied_review_blocks_root_exit=$?
_codex_tied_review_blocks_root_output="$(cat "$_codex_tied_review_blocks_root_mock_dir/output.txt")"
run_test "codex_tied_review_blocks_root_exit_needs_revision" "1" "$_codex_tied_review_blocks_root_exit"
run_test "codex_tied_review_blocks_root_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_tied_review_blocks_root_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_review_blocks_root_mock_dir"
unset _codex_tied_review_blocks_root_mock_dir _codex_tied_review_blocks_root_output _codex_tied_review_blocks_root_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787623071): the
# terminal-evidence tie-break only checked codex_response_is_blocking, so an
# unrecognized-format submitted review tied with a clean SHA-pinned root
# comment lost the tie-break and the clean root comment won, returning
# APPROVED instead of the documented safe-fail NEEDS_REVISION for
# unrecognized responses. Root comment is a clean approval; tied review body
# matches neither the blocking nor approval pattern.
_codex_tied_unrecognized_review_safe_fails_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_unrecognized_review_safe_fails_mock_dir/gh" <<'CODEX_TIED_UNRECOGNIZED_REVIEW_SAFE_FAILS_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deadfeed1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":131,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"deadfeed1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Some ambiguous status update with no recognized marker."}]\n'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":231,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `deadfeed1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_UNRECOGNIZED_REVIEW_SAFE_FAILS_GH
chmod +x "$_codex_tied_unrecognized_review_safe_fails_mock_dir/gh"

_codex_tied_unrecognized_review_safe_fails_output=""
_codex_tied_unrecognized_review_safe_fails_exit=0
PATH="$_codex_tied_unrecognized_review_safe_fails_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_unrecognized_review_safe_fails_mock_dir/output.txt" 2>&1 || _codex_tied_unrecognized_review_safe_fails_exit=$?
_codex_tied_unrecognized_review_safe_fails_output="$(cat "$_codex_tied_unrecognized_review_safe_fails_mock_dir/output.txt")"
run_test "codex_tied_unrecognized_review_safe_fails_exit_needs_revision" "1" "$_codex_tied_unrecognized_review_safe_fails_exit"
run_test "codex_tied_unrecognized_review_safe_fails_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
  "$(printf '%s\n' "$_codex_tied_unrecognized_review_safe_fails_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_unrecognized_review_safe_fails_mock_dir"
unset _codex_tied_unrecognized_review_safe_fails_mock_dir _codex_tied_unrecognized_review_safe_fails_output _codex_tied_unrecognized_review_safe_fails_exit

# A clean submitted review arrives first, then a SHA-pinned BLOCKING root
# comment, then a newer non-terminal acknowledgement comment. Greedily
# selecting the latest root comment overall (the ack) would discard the
# blocking root comment and let the earlier clean review win by default. The
# terminal SHA-pinned comment must be selected independently of the latest
# ancillary comment.
_codex_ack_does_not_erase_blocking_root_mock_dir="$(mktemp -d)"
cat > "$_codex_ack_does_not_erase_blocking_root_mock_dir/gh" <<'CODEX_ACK_DOES_NOT_ERASE_BLOCKING_ROOT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'dead12341234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":130,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"dead12341234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":231,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: root finding before ack.\\n\\n**Reviewed commit:** `dead12341234`"},{"id":232,"created_at":"2026-01-01T00:00:03Z","user":{"login":"chatgpt-codex-connector"},"body":"If Codex has suggestions, it will comment; otherwise it will react with thumbs up."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ACK_DOES_NOT_ERASE_BLOCKING_ROOT_GH
chmod +x "$_codex_ack_does_not_erase_blocking_root_mock_dir/gh"

_codex_ack_does_not_erase_blocking_root_output=""
_codex_ack_does_not_erase_blocking_root_exit=0
PATH="$_codex_ack_does_not_erase_blocking_root_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_ack_does_not_erase_blocking_root_mock_dir/output.txt" 2>&1 || _codex_ack_does_not_erase_blocking_root_exit=$?
_codex_ack_does_not_erase_blocking_root_output="$(cat "$_codex_ack_does_not_erase_blocking_root_mock_dir/output.txt")"
run_test "codex_ack_does_not_erase_blocking_root_exit_needs_revision" "1" "$_codex_ack_does_not_erase_blocking_root_exit"
run_test "codex_ack_does_not_erase_blocking_root_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_ack_does_not_erase_blocking_root_output" | grep "^VERDICT:")"
rm -rf "$_codex_ack_does_not_erase_blocking_root_mock_dir"
unset _codex_ack_does_not_erase_blocking_root_mock_dir _codex_ack_does_not_erase_blocking_root_output _codex_ack_does_not_erase_blocking_root_exit

_codex_async_newer_root_blocks_old_review_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_async_newer_root_blocks_old_review_mock_dir/comment_calls"
printf '0\n' > "$_codex_async_newer_root_blocks_old_review_mock_dir/review_calls"
cat > "$_codex_async_newer_root_blocks_old_review_mock_dir/gh" <<'CODEX_ASYNC_NEWER_ROOT_BLOCKS_OLD_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deaf12341234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":125,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    calls_file="$(dirname "$0")/review_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 2 ]; then
      printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"deaf12341234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 2 ]; then
      printf '[{"id":225,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: newer async root finding.\\n\\n**Reviewed commit:** `deaf1234`"}]\n'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ASYNC_NEWER_ROOT_BLOCKS_OLD_REVIEW_GH
chmod +x "$_codex_async_newer_root_blocks_old_review_mock_dir/gh"

_codex_async_newer_root_blocks_old_review_output=""
_codex_async_newer_root_blocks_old_review_exit=0
PATH="$_codex_async_newer_root_blocks_old_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_async_newer_root_blocks_old_review_mock_dir/output.txt" 2>&1 || _codex_async_newer_root_blocks_old_review_exit=$?
_codex_async_newer_root_blocks_old_review_output="$(cat "$_codex_async_newer_root_blocks_old_review_mock_dir/output.txt")"
run_test "codex_async_newer_root_blocks_old_review_exit_needs_revision" "1" "$_codex_async_newer_root_blocks_old_review_exit"
run_test "codex_async_newer_root_blocks_old_review_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_async_newer_root_blocks_old_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_async_newer_root_blocks_old_review_mock_dir"
unset _codex_async_newer_root_blocks_old_review_mock_dir _codex_async_newer_root_blocks_old_review_output _codex_async_newer_root_blocks_old_review_exit

# Root comments are a terminal evidence source. If the root-comments fetch
# fails specifically during the async grace period while the reviews fetch
# succeeds with a clean review, the failure must be treated as unavailable
# (fail closed) rather than silently falling through to accept the clean
# review as if no root evidence existed (fail open). Sequence: idempotency
# check (call 1, empty) and main-loop poll (call 2, empty) succeed normally;
# the async-grace root-comments fetch (call 3) fails.
_codex_async_root_fetch_failure_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_async_root_fetch_failure_mock_dir/comment_calls"
printf '0\n' > "$_codex_async_root_fetch_failure_mock_dir/review_calls"
cat > "$_codex_async_root_fetch_failure_mock_dir/gh" <<'CODEX_ASYNC_ROOT_FETCH_FAILURE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'fade12341234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":128,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    calls_file="$(dirname "$0")/review_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 2 ]; then
      printf '[{"submitted_at":"2026-01-01T00:00:05Z","commit_id":"fade12341234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 3 ]; then
      echo "simulated transient API failure" >&2
      exit 1
    fi
    printf '[]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ASYNC_ROOT_FETCH_FAILURE_GH
chmod +x "$_codex_async_root_fetch_failure_mock_dir/gh"

_codex_async_root_fetch_failure_output=""
_codex_async_root_fetch_failure_exit=0
PATH="$_codex_async_root_fetch_failure_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_async_root_fetch_failure_mock_dir/output.txt" 2>&1 || _codex_async_root_fetch_failure_exit=$?
_codex_async_root_fetch_failure_output="$(cat "$_codex_async_root_fetch_failure_mock_dir/output.txt")"
run_test "codex_async_root_fetch_failure_exit_unavailable" "2" "$_codex_async_root_fetch_failure_exit"
run_test "codex_async_root_fetch_failure_verdict" \
  "VERDICT: TIMED_OUT — failed to fetch Codex root comments during async grace period (treated as unavailable)" \
  "$(printf '%s\n' "$_codex_async_root_fetch_failure_output" | grep "^VERDICT:")"
if printf '%s\n' "$_codex_async_root_fetch_failure_output" | grep -q "^VERDICT: APPROVED"; then
  _codex_async_root_fetch_failure_approved="yes"
else
  _codex_async_root_fetch_failure_approved="no"
fi
run_test "codex_async_root_fetch_failure_not_approved" "no" "$_codex_async_root_fetch_failure_approved"
rm -rf "$_codex_async_root_fetch_failure_mock_dir"
unset _codex_async_root_fetch_failure_mock_dir _codex_async_root_fetch_failure_output _codex_async_root_fetch_failure_exit _codex_async_root_fetch_failure_approved

_codex_reaction_with_review_mock_dir="$(mktemp -d)"
cat > "$_codex_reaction_with_review_mock_dir/gh" <<'CODEX_REACTION_WITH_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcreviewok1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":106,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:00Z",commit_id:"abcreviewok1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `aaaaaaaaaa` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":206,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector"},"body":"If Codex has suggestions, it will comment; otherwise it will react with thumbs up."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_REACTION_WITH_REVIEW_GH
chmod +x "$_codex_reaction_with_review_mock_dir/gh"

_codex_reaction_with_review_output=""
_codex_reaction_with_review_exit=0
PATH="$_codex_reaction_with_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_reaction_with_review_mock_dir/output.txt" 2>&1 || _codex_reaction_with_review_exit=$?
_codex_reaction_with_review_output="$(cat "$_codex_reaction_with_review_mock_dir/output.txt")"
run_test "codex_reaction_with_current_review_exit_clean" "0" "$_codex_reaction_with_review_exit"
run_test "codex_reaction_with_current_review_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_reaction_with_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_reaction_with_review_mock_dir"
unset _codex_reaction_with_review_mock_dir _codex_reaction_with_review_output _codex_reaction_with_review_exit

_codex_reaction_then_review_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_reaction_then_review_mock_dir/review_calls"
cat > "$_codex_reaction_then_review_mock_dir/gh" <<'CODEX_REACTION_THEN_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abcreactlate1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":117,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    calls_file="$(dirname "$0")/review_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 2 ]; then
      jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"abcreactlate1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `bbbbbbbbbb` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_REACTION_THEN_REVIEW_GH
chmod +x "$_codex_reaction_then_review_mock_dir/gh"

_codex_reaction_then_review_output=""
_codex_reaction_then_review_exit=0
PATH="$_codex_reaction_then_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 2 --max-retriggers 0 \
  >"$_codex_reaction_then_review_mock_dir/output.txt" 2>&1 || _codex_reaction_then_review_exit=$?
_codex_reaction_then_review_output="$(cat "$_codex_reaction_then_review_mock_dir/output.txt")"
run_test "codex_reaction_then_late_review_exit_clean" "0" "$_codex_reaction_then_review_exit"
run_test "codex_reaction_then_late_review_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_reaction_then_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_reaction_then_review_mock_dir"
unset _codex_reaction_then_review_mock_dir _codex_reaction_then_review_output _codex_reaction_then_review_exit

_codex_async_reaction_then_review_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_async_reaction_then_review_mock_dir/review_calls"
cat > "$_codex_async_reaction_then_review_mock_dir/gh" <<'CODEX_ASYNC_REACTION_THEN_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abc456aa1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":122,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
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
      jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"abc456aa1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `cccccccccc` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ASYNC_REACTION_THEN_REVIEW_GH
chmod +x "$_codex_async_reaction_then_review_mock_dir/gh"

_codex_async_reaction_then_review_output=""
_codex_async_reaction_then_review_exit=0
PATH="$_codex_async_reaction_then_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_async_reaction_then_review_mock_dir/output.txt" 2>&1 || _codex_async_reaction_then_review_exit=$?
_codex_async_reaction_then_review_output="$(cat "$_codex_async_reaction_then_review_mock_dir/output.txt")"
run_test "codex_async_reaction_then_late_review_exit_clean" "0" "$_codex_async_reaction_then_review_exit"
run_test "codex_async_reaction_then_late_review_approved" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_async_reaction_then_review_output" | grep "^VERDICT:")"
rm -rf "$_codex_async_reaction_then_review_mock_dir"
unset _codex_async_reaction_then_review_mock_dir _codex_async_reaction_then_review_output _codex_async_reaction_then_review_exit

_codex_async_reaction_environment_mock_dir="$(mktemp -d)"
cat > "$_codex_async_reaction_environment_mock_dir/gh" <<'CODEX_ASYNC_REACTION_ENVIRONMENT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'abc789aa1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":124,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":224,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ASYNC_REACTION_ENVIRONMENT_GH
chmod +x "$_codex_async_reaction_environment_mock_dir/gh"

_codex_async_reaction_environment_output=""
_codex_async_reaction_environment_exit=0
PATH="$_codex_async_reaction_environment_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_async_reaction_environment_mock_dir/output.txt" 2>&1 || _codex_async_reaction_environment_exit=$?
_codex_async_reaction_environment_output="$(cat "$_codex_async_reaction_environment_mock_dir/output.txt")"
run_test "codex_async_reaction_environment_exit_unavailable" "2" "$_codex_async_reaction_environment_exit"
run_test "codex_async_reaction_environment_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_async_reaction_environment_output" | grep "^REASON=")"
rm -rf "$_codex_async_reaction_environment_mock_dir"
unset _codex_async_reaction_environment_mock_dir _codex_async_reaction_environment_output _codex_async_reaction_environment_exit

# Reproduces Codex finding 3786691880-followup (P2, comment id 3787460055):
# the final acknowledgement re-poll must preserve a recorded environment
# setup error instead of returning reaction-without-review when a thumbs-up
# reaction is also present. Sequence: initial async-grace poll finds the
# acknowledgement comment (no review, no reaction yet) -> sleeps -> final
# re-poll finds an environment-setup comment (sets SEEN_ENVIRONMENT_ERROR)
# -> trigger reactions endpoint reports a thumbs-up -> expect
# codex-github-environment-missing, not codex-github-reaction-without-review.
_codex_ack_repoll_env_then_reaction_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_ack_repoll_env_then_reaction_mock_dir/comment_calls"
cat > "$_codex_ack_repoll_env_then_reaction_mock_dir/gh" <<'CODEX_ACK_REPOLL_ENV_THEN_REACTION_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'ackrepoll1234567890a\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":126,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    # Calls 1-2 are the pre-trigger dedup check and the main poll-loop's
    # bot-response check; both must stay empty so execution falls through
    # to the async-arrival grace poll (call 3) and its final re-poll
    # (call 4+).
    if [ "$calls" -ge 4 ]; then
      printf '[{"id":227,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    elif [ "$calls" -eq 3 ]; then
      printf '[{"id":226,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"If Codex has suggestions, it will comment; otherwise it will react with 👍 on this comment."}]\n'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ACK_REPOLL_ENV_THEN_REACTION_GH
chmod +x "$_codex_ack_repoll_env_then_reaction_mock_dir/gh"

_codex_ack_repoll_env_then_reaction_output=""
_codex_ack_repoll_env_then_reaction_exit=0
PATH="$_codex_ack_repoll_env_then_reaction_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_ack_repoll_env_then_reaction_mock_dir/output.txt" 2>&1 || _codex_ack_repoll_env_then_reaction_exit=$?
_codex_ack_repoll_env_then_reaction_output="$(cat "$_codex_ack_repoll_env_then_reaction_mock_dir/output.txt")"
run_test "codex_ack_repoll_env_then_reaction_exit_unavailable" "2" "$_codex_ack_repoll_env_then_reaction_exit"
run_test "codex_ack_repoll_env_then_reaction_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_ack_repoll_env_then_reaction_output" | grep "^REASON=")"
rm -rf "$_codex_ack_repoll_env_then_reaction_mock_dir"
unset _codex_ack_repoll_env_then_reaction_mock_dir _codex_ack_repoll_env_then_reaction_output _codex_ack_repoll_env_then_reaction_exit

# Reproduces PR-Agent advisory finding on PR #1490 (main-loop env-error
# override): the main poll loop recorded an environment setup error on its
# first iteration (SEEN_ENVIRONMENT_ERROR=1) but a later iteration's
# same-timestamp-or-older submitted review still exited APPROVED without
# checking that flag, silently discarding the recorded environment failure.
# Sequence: iteration 1 finds an environment-setup root comment -> iteration
# 2 finds no new comment but a clean current-head review AT THE SAME
# TIMESTAMP as the recorded environment error -> expect
# codex-github-environment-missing, not APPROVED (ties favor the non-clean
# evidence, per codex_response_requires_attention's tie-break principle).
# Covers all four APPROVED exit sites' shared guard, exercised here via the
# main poll loop. A strictly NEWER review is expected to supersede the
# stale environment error instead — see
# codex_main_loop_env_then_newer_review_supersedes below.
#
# The review body must reproduce a real CODEX_APPROVED_TEMPLATES entry
# (issue #1491's conservative-verdict-classifier implementation plan): the
# SEEN_ENVIRONMENT_ERROR-supersede check this scenario exercises lives
# INSIDE the `source == "review" && codex_response_is_approved` branch, so
# a body that does not exactly reproduce the template never reaches that
# check at all (it falls through to the unrecognized-format safe-fail
# instead) — silently defeating this scenario's own coverage rather than
# failing loudly, which is exactly why this fixture needed updating
# alongside the classifier redesign even though its own assertion never
# mentions "APPROVED".
_codex_main_loop_env_then_review_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_main_loop_env_then_review_mock_dir/comment_calls"
printf '0\n' > "$_codex_main_loop_env_then_review_mock_dir/review_calls"
cat > "$_codex_main_loop_env_then_review_mock_dir/gh" <<'CODEX_MAIN_LOOP_ENV_THEN_REVIEW_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'mainloopenv1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":130,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    calls_file="$(dirname "$0")/review_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 2 ]; then
      jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"mainloopenv1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `1111111111` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -eq 2 ]; then
      printf '[{"id":230,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MAIN_LOOP_ENV_THEN_REVIEW_GH
chmod +x "$_codex_main_loop_env_then_review_mock_dir/gh"

_codex_main_loop_env_then_review_output=""
_codex_main_loop_env_then_review_exit=0
PATH="$_codex_main_loop_env_then_review_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 2 --max-retriggers 0 \
  >"$_codex_main_loop_env_then_review_mock_dir/output.txt" 2>&1 || _codex_main_loop_env_then_review_exit=$?
_codex_main_loop_env_then_review_output="$(cat "$_codex_main_loop_env_then_review_mock_dir/output.txt")"
run_test "codex_main_loop_env_then_review_exit_unavailable" "2" "$_codex_main_loop_env_then_review_exit"
run_test "codex_main_loop_env_then_review_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_main_loop_env_then_review_output" | grep "^REASON=")"
rm -rf "$_codex_main_loop_env_then_review_mock_dir"
unset _codex_main_loop_env_then_review_mock_dir _codex_main_loop_env_then_review_output _codex_main_loop_env_then_review_exit

# Reproduces Codex finding on PR #1490 (P2, comment id 3787679406): the
# environment-error guard must not be permanently sticky — a genuinely
# fresh (strictly newer timestamp) current-head approved review must
# supersede a now-stale recorded environment error, so an operator fixing
# the Codex cloud environment mid-poll can recover within the same
# invocation. Sequence identical to codex_main_loop_env_then_review above,
# except the review's submitted_at is strictly newer than the env-error
# comment's created_at -> expect APPROVED, not environment-missing.
_codex_main_loop_env_then_newer_review_supersedes_mock_dir="$(mktemp -d)"
printf '0\n' > "$_codex_main_loop_env_then_newer_review_supersedes_mock_dir/comment_calls"
printf '0\n' > "$_codex_main_loop_env_then_newer_review_supersedes_mock_dir/review_calls"
cat > "$_codex_main_loop_env_then_newer_review_supersedes_mock_dir/gh" <<'CODEX_MAIN_LOOP_ENV_THEN_NEWER_REVIEW_SUPERSEDES_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'newerreview1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":132,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    calls_file="$(dirname "$0")/review_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -ge 2 ]; then
      jq -nc '[{submitted_at:"2026-01-01T00:00:03Z",commit_id:"newerreview1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `dddddddddd` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment \"@codex review\". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting \"@codex address that feedback\". </details>")}]'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *"issues/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -eq 2 ]; then
      printf '[{"id":230,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    else
      printf '[]\n'
    fi
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_MAIN_LOOP_ENV_THEN_NEWER_REVIEW_SUPERSEDES_GH
chmod +x "$_codex_main_loop_env_then_newer_review_supersedes_mock_dir/gh"

_codex_main_loop_env_then_newer_review_supersedes_output=""
_codex_main_loop_env_then_newer_review_supersedes_exit=0
PATH="$_codex_main_loop_env_then_newer_review_supersedes_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 2 --max-retriggers 0 \
  >"$_codex_main_loop_env_then_newer_review_supersedes_mock_dir/output.txt" 2>&1 || _codex_main_loop_env_then_newer_review_supersedes_exit=$?
_codex_main_loop_env_then_newer_review_supersedes_output="$(cat "$_codex_main_loop_env_then_newer_review_supersedes_mock_dir/output.txt")"
run_test "codex_main_loop_env_then_newer_review_supersedes_exit_clean" "0" "$_codex_main_loop_env_then_newer_review_supersedes_exit"
run_test "codex_main_loop_env_then_newer_review_supersedes_verdict" "VERDICT: APPROVED" \
  "$(printf '%s\n' "$_codex_main_loop_env_then_newer_review_supersedes_output" | grep "^VERDICT:")"
rm -rf "$_codex_main_loop_env_then_newer_review_supersedes_mock_dir"
unset _codex_main_loop_env_then_newer_review_supersedes_mock_dir _codex_main_loop_env_then_newer_review_supersedes_output _codex_main_loop_env_then_newer_review_supersedes_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787679402): the
# codex_response_requires_attention tie-break helper (added in the prior
# cycle to fix unrecognized-format ties) checked only the approval pattern,
# so a mixed response containing BOTH an approval phrase and a blocking
# marker (e.g. "No blocking issues found. Must fix ...") was misclassified
# as a clean approval and lost the tie-break to a clean root comment,
# producing APPROVED instead of the classifier's blocking-first
# NEEDS_REVISION. Root comment is a clean approval; tied review body
# contains both an approval phrase and a blocking marker.
_codex_tied_mixed_blocking_review_wins_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_mixed_blocking_review_wins_mock_dir/gh" <<'CODEX_TIED_MIXED_BLOCKING_REVIEW_WINS_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deadb00d12345678\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":133,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"deadb00d12345678","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found. Must fix the typo on line 4."}]\n'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":234,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `deadb00d1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_MIXED_BLOCKING_REVIEW_WINS_GH
chmod +x "$_codex_tied_mixed_blocking_review_wins_mock_dir/gh"

_codex_tied_mixed_blocking_review_wins_output=""
_codex_tied_mixed_blocking_review_wins_exit=0
PATH="$_codex_tied_mixed_blocking_review_wins_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_mixed_blocking_review_wins_mock_dir/output.txt" 2>&1 || _codex_tied_mixed_blocking_review_wins_exit=$?
_codex_tied_mixed_blocking_review_wins_output="$(cat "$_codex_tied_mixed_blocking_review_wins_mock_dir/output.txt")"
run_test "codex_tied_mixed_blocking_review_wins_exit_needs_revision" "1" "$_codex_tied_mixed_blocking_review_wins_exit"
run_test "codex_tied_mixed_blocking_review_wins_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_tied_mixed_blocking_review_wins_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_mixed_blocking_review_wins_mock_dir"
unset _codex_tied_mixed_blocking_review_wins_mock_dir _codex_tied_mixed_blocking_review_wins_output _codex_tied_mixed_blocking_review_wins_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787786942): a
# submitted review body that exceeds a pipe buffer's capacity (well within
# GitHub's ~64KB per-comment limit) causes `jq ... | head -c 5000` to SIGPIPE
# jq once `head` closes its read end after 5000 bytes; under `set -euo
# pipefail` this aborts the whole script with exit 141 before any VERDICT
# line is emitted. Truncation now happens inside jq (codepoint slice)
# instead of via a piped `head`, eliminating the SIGPIPE entirely. Body is
# built via jq's own string-repeat operator (200000 chars) rather than a
# large literal in this file or a python3 dependency.
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign:
# this body's leading "No blocking issues found." prefix was a pre-plan
# block-list vocabulary artifact, not a reproduction of
# CODEX_APPROVED_TEMPLATES' whole-body exact template, so it now correctly
# safe-fails to NEEDS_REVISION. The scenario's actual purpose — proving a
# large (~200,000-character) response completes without a SIGPIPE crash —
# is unaffected by the verdict changing; only the disposition changes.
_codex_long_review_body_no_sigpipe_mock_dir="$(mktemp -d)"
cat > "$_codex_long_review_body_no_sigpipe_mock_dir/gh" <<'CODEX_LONG_REVIEW_BODY_NO_SIGPIPE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'longbody1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":140,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    jq -nc '[{submitted_at:"2026-01-01T00:00:01Z",commit_id:"longbody1234567890",user:{login:"chatgpt-codex-connector[bot]"},body:("No blocking issues found. " + ("x" * 200000))}]'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_LONG_REVIEW_BODY_NO_SIGPIPE_GH
chmod +x "$_codex_long_review_body_no_sigpipe_mock_dir/gh"

_codex_long_review_body_no_sigpipe_output=""
_codex_long_review_body_no_sigpipe_exit=0
PATH="$_codex_long_review_body_no_sigpipe_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_long_review_body_no_sigpipe_mock_dir/output.txt" 2>&1 || _codex_long_review_body_no_sigpipe_exit=$?
_codex_long_review_body_no_sigpipe_output="$(cat "$_codex_long_review_body_no_sigpipe_mock_dir/output.txt")"
run_test "codex_long_review_body_no_sigpipe_exit_needs_revision" "1" "$_codex_long_review_body_no_sigpipe_exit"
run_test "codex_long_review_body_no_sigpipe_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
  "$(printf '%s\n' "$_codex_long_review_body_no_sigpipe_output" | grep "^VERDICT:")"
rm -rf "$_codex_long_review_body_no_sigpipe_mock_dir"
unset _codex_long_review_body_no_sigpipe_mock_dir _codex_long_review_body_no_sigpipe_output _codex_long_review_body_no_sigpipe_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787786943): within a
# single poll, a clean submitted review at T1 and a newer environment-setup
# root comment at T2 were combined by unconditionally preferring the review
# (since it wasn't competing against a SHA-pinned terminal comment), so the
# newer setup failure never had a chance to be recorded as
# SEEN_ENVIRONMENT_ERROR and the run returned APPROVED. Root comment (env
# error) is strictly newer than the review in this fixture -> expect
# codex-github-environment-missing, not APPROVED.
_codex_same_poll_newer_env_error_wins_mock_dir="$(mktemp -d)"
cat > "$_codex_same_poll_newer_env_error_wins_mock_dir/gh" <<'CODEX_SAME_POLL_NEWER_ENV_ERROR_WINS_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'samepoll1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":141,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"samepoll1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":242,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_SAME_POLL_NEWER_ENV_ERROR_WINS_GH
chmod +x "$_codex_same_poll_newer_env_error_wins_mock_dir/gh"

_codex_same_poll_newer_env_error_wins_output=""
_codex_same_poll_newer_env_error_wins_exit=0
PATH="$_codex_same_poll_newer_env_error_wins_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_same_poll_newer_env_error_wins_mock_dir/output.txt" 2>&1 || _codex_same_poll_newer_env_error_wins_exit=$?
_codex_same_poll_newer_env_error_wins_output="$(cat "$_codex_same_poll_newer_env_error_wins_mock_dir/output.txt")"
run_test "codex_same_poll_newer_env_error_wins_exit_unavailable" "2" "$_codex_same_poll_newer_env_error_wins_exit"
run_test "codex_same_poll_newer_env_error_wins_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_same_poll_newer_env_error_wins_output" | grep "^REASON=")"
rm -rf "$_codex_same_poll_newer_env_error_wins_mock_dir"
unset _codex_same_poll_newer_env_error_wins_mock_dir _codex_same_poll_newer_env_error_wins_output _codex_same_poll_newer_env_error_wins_exit

# Reproduces Codex finding on PR #1490 (P2, comment id 3787786945): when the
# same comments fetch contains an environment-setup error at T1 followed by
# a plain acknowledgement at T2, codex_scan_comment_evidence previously kept
# only the LATEST comment overall (the acknowledgement), losing the
# actionable setup-error text. Combined with a thumbs-up reaction, this
# produced codex-github-reaction-without-review instead of
# codex-github-environment-missing. Async-arrival grace path: env-error at
# T1 and acknowledgement at T2 both appear in the same async-arrival poll's
# comment fetch, plus a thumbs-up reaction on the trigger comment.
_codex_env_error_survives_later_ack_mock_dir="$(mktemp -d)"
cat > "$_codex_env_error_survives_later_ack_mock_dir/gh" <<'CODEX_ENV_ERROR_SURVIVES_LATER_ACK_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'ackenverr1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":142,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":243,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."},{"id":244,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"If Codex has suggestions, it will comment; otherwise it will react with \xf0\x9f\x91\x8d on this comment."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_ENV_ERROR_SURVIVES_LATER_ACK_GH
chmod +x "$_codex_env_error_survives_later_ack_mock_dir/gh"

_codex_env_error_survives_later_ack_output=""
_codex_env_error_survives_later_ack_exit=0
PATH="$_codex_env_error_survives_later_ack_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_env_error_survives_later_ack_mock_dir/output.txt" 2>&1 || _codex_env_error_survives_later_ack_exit=$?
_codex_env_error_survives_later_ack_output="$(cat "$_codex_env_error_survives_later_ack_mock_dir/output.txt")"
run_test "codex_env_error_survives_later_ack_exit_unavailable" "2" "$_codex_env_error_survives_later_ack_exit"
run_test "codex_env_error_survives_later_ack_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_env_error_survives_later_ack_output" | grep "^REASON=")"
rm -rf "$_codex_env_error_survives_later_ack_mock_dir"
unset _codex_env_error_survives_later_ack_mock_dir _codex_env_error_survives_later_ack_output _codex_env_error_survives_later_ack_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787868727): a clean
# SHA-pinned terminal root comment at T1 and a strictly newer
# environment-setup-error comment at T2, both present in the same comments
# fetch. codex_combine_terminal_evidence previously chose the terminal
# comment unconditionally whenever no submitted review was present,
# discarding the newer environment error entirely (that branch never
# considered it). No review from the reviews endpoint -> expect
# codex-github-environment-missing, not APPROVED.
_codex_terminal_comment_vs_newer_env_error_mock_dir="$(mktemp -d)"
cat > "$_codex_terminal_comment_vs_newer_env_error_mock_dir/gh" <<'CODEX_TERMINAL_COMMENT_VS_NEWER_ENV_ERROR_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deadf00d12345678\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":150,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":250,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `deadf00d1234`"},{"id":251,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TERMINAL_COMMENT_VS_NEWER_ENV_ERROR_GH
chmod +x "$_codex_terminal_comment_vs_newer_env_error_mock_dir/gh"

_codex_terminal_comment_vs_newer_env_error_output=""
_codex_terminal_comment_vs_newer_env_error_exit=0
PATH="$_codex_terminal_comment_vs_newer_env_error_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_terminal_comment_vs_newer_env_error_mock_dir/output.txt" 2>&1 || _codex_terminal_comment_vs_newer_env_error_exit=$?
_codex_terminal_comment_vs_newer_env_error_output="$(cat "$_codex_terminal_comment_vs_newer_env_error_mock_dir/output.txt")"
run_test "codex_terminal_comment_vs_newer_env_error_exit_unavailable" "2" "$_codex_terminal_comment_vs_newer_env_error_exit"
run_test "codex_terminal_comment_vs_newer_env_error_reason" "REASON=codex-github-environment-missing" \
  "$(printf '%s\n' "$_codex_terminal_comment_vs_newer_env_error_output" | grep "^REASON=")"
rm -rf "$_codex_terminal_comment_vs_newer_env_error_mock_dir"
unset _codex_terminal_comment_vs_newer_env_error_mock_dir _codex_terminal_comment_vs_newer_env_error_output _codex_terminal_comment_vs_newer_env_error_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787868733): only
# submitted review bodies were sliced inside jq; a SHA-pinned root-comment
# body large enough to exceed a pipe buffer's capacity (well within
# GitHub's ~64KB per-comment limit) still passed through
# `printf | head -c 10000` in the main loop and all 3 async paths,
# triggering the same SIGPIPE/exit-141 crash under `set -euo pipefail`.
# All 4 sites now truncate via `jq -Rrs '.[0:10000]'`, which slurps its
# entire stdin before producing output so the writer can never receive
# SIGPIPE regardless of input size.
#
# Retargeted for issue #1491's conservative-verdict-classifier redesign:
# this body (verdict sentence + 200,000 filler characters + Reviewed-commit
# marker, no footer) does not reproduce CODEX_APPROVED_TEMPLATES' whole-body
# exact template, so it now correctly safe-fails to NEEDS_REVISION. The
# scenario's actual purpose — proving a large root-comment body completes
# without a SIGPIPE crash — is unaffected by the verdict changing; only the
# disposition changes.
_codex_long_root_comment_no_sigpipe_mock_dir="$(mktemp -d)"
cat > "$_codex_long_root_comment_no_sigpipe_mock_dir/gh" <<'CODEX_LONG_ROOT_COMMENT_NO_SIGPIPE_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deadf00d12345678\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":151,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    jq -nc '[{id:260,created_at:"2026-01-01T00:00:01Z",user:{login:"chatgpt-codex-connector[bot]"},body:("Codex Review: Didn'"'"'t find any major issues.\n\n" + ("x" * 200000) + "\n\n**Reviewed commit:** `deadf00d1234`")}]'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_LONG_ROOT_COMMENT_NO_SIGPIPE_GH
chmod +x "$_codex_long_root_comment_no_sigpipe_mock_dir/gh"

_codex_long_root_comment_no_sigpipe_output=""
_codex_long_root_comment_no_sigpipe_exit=0
PATH="$_codex_long_root_comment_no_sigpipe_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_long_root_comment_no_sigpipe_mock_dir/output.txt" 2>&1 || _codex_long_root_comment_no_sigpipe_exit=$?
_codex_long_root_comment_no_sigpipe_output="$(cat "$_codex_long_root_comment_no_sigpipe_mock_dir/output.txt")"
run_test "codex_long_root_comment_no_sigpipe_exit_needs_revision" "1" "$_codex_long_root_comment_no_sigpipe_exit"
run_test "codex_long_root_comment_no_sigpipe_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
  "$(printf '%s\n' "$_codex_long_root_comment_no_sigpipe_output" | grep "^VERDICT:")"
rm -rf "$_codex_long_root_comment_no_sigpipe_mock_dir"
unset _codex_long_root_comment_no_sigpipe_mock_dir _codex_long_root_comment_no_sigpipe_output _codex_long_root_comment_no_sigpipe_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3787943162): a
# SHA-pinned terminal root comment reporting a blocking finding at T1,
# followed by a non-terminal environment-setup comment at T2 in the same
# fetch. codex_combine_terminal_evidence's final environment-error override
# previously replaced the blocking COMBINED_BODY whenever it was not
# strictly newer than the environment-error comment, silently hiding the
# blocking finding behind an "unavailable" verdict. Blocking terminal
# evidence must now win outright, regardless of timing. No review from the
# reviews endpoint -> expect NEEDS_REVISION, not environment-missing.
_codex_blocking_terminal_beats_env_error_mock_dir="$(mktemp -d)"
cat > "$_codex_blocking_terminal_beats_env_error_mock_dir/gh" <<'CODEX_BLOCKING_TERMINAL_BEATS_ENV_ERROR_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'beadf00d1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":160,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":270,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: must fix the null check.\\n\\n**Reviewed commit:** `beadf00d1234`"},{"id":271,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"To use Codex here, create an environment for this repo."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_BLOCKING_TERMINAL_BEATS_ENV_ERROR_GH
chmod +x "$_codex_blocking_terminal_beats_env_error_mock_dir/gh"

_codex_blocking_terminal_beats_env_error_output=""
_codex_blocking_terminal_beats_env_error_exit=0
PATH="$_codex_blocking_terminal_beats_env_error_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_blocking_terminal_beats_env_error_mock_dir/output.txt" 2>&1 || _codex_blocking_terminal_beats_env_error_exit=$?
_codex_blocking_terminal_beats_env_error_output="$(cat "$_codex_blocking_terminal_beats_env_error_mock_dir/output.txt")"
run_test "codex_blocking_terminal_beats_env_error_exit_needs_revision" "1" "$_codex_blocking_terminal_beats_env_error_exit"
run_test "codex_blocking_terminal_beats_env_error_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_blocking_terminal_beats_env_error_output" | grep "^VERDICT:")"
rm -rf "$_codex_blocking_terminal_beats_env_error_mock_dir"
unset _codex_blocking_terminal_beats_env_error_mock_dir _codex_blocking_terminal_beats_env_error_output _codex_blocking_terminal_beats_env_error_exit

# Reproduces Codex finding on PR #1490 (P2, comment id 3787943163): a
# SHA-pinned terminal root review whose blocking finding text quotes the
# environment-setup sentence verbatim (e.g. flagging stale docs that
# reproduce it) was misclassified as an environment-setup error by the
# unanchored substring matcher, suppressing NEEDS_REVISION. A SHA-pinned
# TERMINAL comment is now never classified as an environment error,
# regardless of its text content -> expect NEEDS_REVISION.
_codex_quoted_setup_sentence_in_blocking_finding_mock_dir="$(mktemp -d)"
cat > "$_codex_quoted_setup_sentence_in_blocking_finding_mock_dir/gh" <<'CODEX_QUOTED_SETUP_SENTENCE_IN_BLOCKING_FINDING_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'cafebabe1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":161,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":280,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: docs must not claim: To use Codex here, create an environment for this repo.\\n\\n**Reviewed commit:** `cafebabe1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_QUOTED_SETUP_SENTENCE_IN_BLOCKING_FINDING_GH
chmod +x "$_codex_quoted_setup_sentence_in_blocking_finding_mock_dir/gh"

_codex_quoted_setup_sentence_in_blocking_finding_output=""
_codex_quoted_setup_sentence_in_blocking_finding_exit=0
PATH="$_codex_quoted_setup_sentence_in_blocking_finding_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_quoted_setup_sentence_in_blocking_finding_mock_dir/output.txt" 2>&1 || _codex_quoted_setup_sentence_in_blocking_finding_exit=$?
_codex_quoted_setup_sentence_in_blocking_finding_output="$(cat "$_codex_quoted_setup_sentence_in_blocking_finding_mock_dir/output.txt")"
run_test "codex_quoted_setup_sentence_in_blocking_finding_exit_needs_revision" "1" "$_codex_quoted_setup_sentence_in_blocking_finding_exit"
run_test "codex_quoted_setup_sentence_in_blocking_finding_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_quoted_setup_sentence_in_blocking_finding_output" | grep "^VERDICT:")"
rm -rf "$_codex_quoted_setup_sentence_in_blocking_finding_mock_dir"
unset _codex_quoted_setup_sentence_in_blocking_finding_mock_dir _codex_quoted_setup_sentence_in_blocking_finding_output _codex_quoted_setup_sentence_in_blocking_finding_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3788008326): when
# multiple current-head reviews share GitHub's second-resolution
# submitted_at timestamp, `sort_by(.submitted_at) | last` discarded every
# response except whichever the API happened to return last, regardless of
# content. A blocking review returned BEFORE a tied clean review in the
# array silently produced APPROVED. The review-poll jq queries now select
# every review tied at the latest timestamp and codex_select_review_evidence
# picks the one requiring attention, if any. Fixture: blocking review first
# in the array, clean review second, both tied at the same timestamp.
_codex_tied_reviews_blocking_first_survives_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_reviews_blocking_first_survives_mock_dir/gh" <<'CODEX_TIED_REVIEWS_BLOCKING_FIRST_SURVIVES_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'deadbeef1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":170,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"deadbeef1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: must fix the leak."},{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"deadbeef1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_REVIEWS_BLOCKING_FIRST_SURVIVES_GH
chmod +x "$_codex_tied_reviews_blocking_first_survives_mock_dir/gh"

_codex_tied_reviews_blocking_first_survives_output=""
_codex_tied_reviews_blocking_first_survives_exit=0
PATH="$_codex_tied_reviews_blocking_first_survives_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_reviews_blocking_first_survives_mock_dir/output.txt" 2>&1 || _codex_tied_reviews_blocking_first_survives_exit=$?
_codex_tied_reviews_blocking_first_survives_output="$(cat "$_codex_tied_reviews_blocking_first_survives_mock_dir/output.txt")"
run_test "codex_tied_reviews_blocking_first_survives_exit_needs_revision" "1" "$_codex_tied_reviews_blocking_first_survives_exit"
run_test "codex_tied_reviews_blocking_first_survives_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_tied_reviews_blocking_first_survives_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_reviews_blocking_first_survives_mock_dir"
unset _codex_tied_reviews_blocking_first_survives_mock_dir _codex_tied_reviews_blocking_first_survives_output _codex_tied_reviews_blocking_first_survives_exit

# Reproduces Codex finding on PR #1490 (P2, comment id 3788008327): only
# environment-error ancillary comments were retained/compared independently
# — usage-limit comments were not, so an older clean current-head review
# and a newer root comment reporting exhausted Codex usage silently
# resolved to APPROVED instead of the configured unavailable policy.
# codex_scan_comment_evidence and the final override in
# codex_combine_terminal_evidence now treat usage-limit comments the same
# way as environment-error comments.
_codex_older_review_vs_newer_usage_limit_mock_dir="$(mktemp -d)"
cat > "$_codex_older_review_vs_newer_usage_limit_mock_dir/gh" <<'CODEX_OLDER_REVIEW_VS_NEWER_USAGE_LIMIT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'facefeed1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":180,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"facefeed1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"No blocking issues found."}]\n'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":290,"created_at":"2026-01-01T00:00:02Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"You have reached your Codex usage limits for code reviews."}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_OLDER_REVIEW_VS_NEWER_USAGE_LIMIT_GH
chmod +x "$_codex_older_review_vs_newer_usage_limit_mock_dir/gh"

_codex_older_review_vs_newer_usage_limit_output=""
_codex_older_review_vs_newer_usage_limit_exit=0
PATH="$_codex_older_review_vs_newer_usage_limit_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_older_review_vs_newer_usage_limit_mock_dir/output.txt" 2>&1 || _codex_older_review_vs_newer_usage_limit_exit=$?
_codex_older_review_vs_newer_usage_limit_output="$(cat "$_codex_older_review_vs_newer_usage_limit_mock_dir/output.txt")"
run_test "codex_older_review_vs_newer_usage_limit_exit_unavailable" "3" "$_codex_older_review_vs_newer_usage_limit_exit"
run_test "codex_older_review_vs_newer_usage_limit_reason" "REASON=codex-github-usage-limit" \
  "$(printf '%s\n' "$_codex_older_review_vs_newer_usage_limit_output" | grep "^REASON=")"
rm -rf "$_codex_older_review_vs_newer_usage_limit_mock_dir"
unset _codex_older_review_vs_newer_usage_limit_mock_dir _codex_older_review_vs_newer_usage_limit_output _codex_older_review_vs_newer_usage_limit_exit

# Reproduces Codex finding on PR #1490 (P1, comment id 3788078189): when
# two current-head terminal root comments share GitHub's second-resolution
# timestamp, codex_scan_comment_evidence previously overwrote
# COMMENT_TERMINAL_BODY unconditionally on every terminal comment seen,
# regardless of content. A blocking terminal comment followed by a tied
# clean terminal comment silently produced APPROVED. The not-a-clean-
# approval-first tie-break now decides which tied terminal comment is
# tracked. Fixture: blocking terminal comment first, clean terminal
# comment second, both tied at the same timestamp, no review.
_codex_tied_terminal_comments_blocking_survives_mock_dir="$(mktemp -d)"
cat > "$_codex_tied_terminal_comments_blocking_survives_mock_dir/gh" <<'CODEX_TIED_TERMINAL_COMMENTS_BLOCKING_SURVIVES_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'aceface1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":190,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"id":300,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: must fix the leak.\\n\\n**Reviewed commit:** `aceface1234`"},{"id":301,"created_at":"2026-01-01T00:00:01Z","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Codex Review: Didn'\''t find any major issues.\\n\\n**Reviewed commit:** `aceface1234`"}]\n'
    exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_TIED_TERMINAL_COMMENTS_BLOCKING_SURVIVES_GH
chmod +x "$_codex_tied_terminal_comments_blocking_survives_mock_dir/gh"

_codex_tied_terminal_comments_blocking_survives_output=""
_codex_tied_terminal_comments_blocking_survives_exit=0
PATH="$_codex_tied_terminal_comments_blocking_survives_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_tied_terminal_comments_blocking_survives_mock_dir/output.txt" 2>&1 || _codex_tied_terminal_comments_blocking_survives_exit=$?
_codex_tied_terminal_comments_blocking_survives_output="$(cat "$_codex_tied_terminal_comments_blocking_survives_mock_dir/output.txt")"
run_test "codex_tied_terminal_comments_blocking_survives_exit_needs_revision" "1" "$_codex_tied_terminal_comments_blocking_survives_exit"
run_test "codex_tied_terminal_comments_blocking_survives_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_tied_terminal_comments_blocking_survives_output" | grep "^VERDICT:")"
rm -rf "$_codex_tied_terminal_comments_blocking_survives_mock_dir"
unset _codex_tied_terminal_comments_blocking_survives_mock_dir _codex_tied_terminal_comments_blocking_survives_output _codex_tied_terminal_comments_blocking_survives_exit

# Reproduces Codex finding on PR #1490 (P2, comment id 3788078191): the
# usage-limit check ran before the blocking check in every verdict path, so
# a current-head submitted review whose blocking finding text mentions
# "usage limit" as part of the finding itself (e.g. flagging stale docs
# that describe it) was misrouted to an UNAVAILABLE/usage-limit verdict
# before the blocking classifier could run, hiding the actionable finding.
# Blocking is now checked first in every verdict path.
_codex_blocking_text_mentions_usage_limit_mock_dir="$(mktemp -d)"
cat > "$_codex_blocking_text_mentions_usage_limit_mock_dir/gh" <<'CODEX_BLOCKING_TEXT_MENTIONS_USAGE_LIMIT_GH'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*)
    exit 0 ;;
  *"pr view"*headRefOid*)
    printf 'baadf00d1234567890\n'; exit 0 ;;
  *"--method POST"*)
    printf '{"id":191,"created_at":"2026-01-01T00:00:00Z"}\n'; exit 0 ;;
  *"issues/comments/"*"/reactions"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"submitted_at":"2026-01-01T00:00:01Z","commit_id":"baadf00d1234567890","user":{"login":"chatgpt-codex-connector[bot]"},"body":"Blocking issues: docs incorrectly describe the Codex usage limit for code reviews."}]\n'
    exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf 'ERROR=unexpected-gh-invocation\n' >&2
    printf 'ARGS=%q\n' "$*" >&2
    exit 64 ;;
esac
CODEX_BLOCKING_TEXT_MENTIONS_USAGE_LIMIT_GH
chmod +x "$_codex_blocking_text_mentions_usage_limit_mock_dir/gh"

_codex_blocking_text_mentions_usage_limit_output=""
_codex_blocking_text_mentions_usage_limit_exit=0
PATH="$_codex_blocking_text_mentions_usage_limit_mock_dir:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/codex-github-reviewer.sh" \
  42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0 \
  >"$_codex_blocking_text_mentions_usage_limit_mock_dir/output.txt" 2>&1 || _codex_blocking_text_mentions_usage_limit_exit=$?
_codex_blocking_text_mentions_usage_limit_output="$(cat "$_codex_blocking_text_mentions_usage_limit_mock_dir/output.txt")"
run_test "codex_blocking_text_mentions_usage_limit_exit_needs_revision" "1" "$_codex_blocking_text_mentions_usage_limit_exit"
run_test "codex_blocking_text_mentions_usage_limit_verdict" "VERDICT: NEEDS_REVISION" \
  "$(printf '%s\n' "$_codex_blocking_text_mentions_usage_limit_output" | grep "^VERDICT:")"
rm -rf "$_codex_blocking_text_mentions_usage_limit_mock_dir"
unset _codex_blocking_text_mentions_usage_limit_mock_dir _codex_blocking_text_mentions_usage_limit_output _codex_blocking_text_mentions_usage_limit_exit

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
run_test "codex_bodyless_tied_review_needs_revision_exit" "1" "$_codex_bodyless_tied_review_needs_revision_exit"
run_test "codex_bodyless_tied_review_needs_revision_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_tied_reviews_blocking_beats_usage_limit_exit_needs_revision" "1" "$_codex_tied_reviews_blocking_beats_usage_limit_exit"
run_test "codex_tied_reviews_blocking_beats_usage_limit_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_terminal_usage_limit_vs_blocking_review_exit_needs_revision" "1" "$_codex_terminal_usage_limit_vs_blocking_review_exit"
run_test "codex_terminal_usage_limit_vs_blocking_review_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_two_tied_terminal_comments_usage_limit_vs_blocking_exit_needs_revision" "1" "$_codex_two_tied_terminal_comments_usage_limit_vs_blocking_exit"
run_test "codex_two_tied_terminal_comments_usage_limit_vs_blocking_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_tied_usage_limit_then_unrecognized_exit" "1" "$_codex_tied_usage_limit_then_unrecognized_exit"
run_test "codex_tied_usage_limit_then_unrecognized_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_long_root_review_blocker_past_cutoff_exit_needs_revision" "1" "$_codex_long_root_review_blocker_past_cutoff_exit"
run_test "codex_long_root_review_blocker_past_cutoff_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_long_review_blocker_past_query_cutoff_exit_needs_revision" "1" "$_codex_long_review_blocker_past_query_cutoff_exit"
run_test "codex_long_review_blocker_past_query_cutoff_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_negated_approval_root_comment_exit_needs_revision" "1" "$_codex_negated_approval_root_comment_exit"
run_test "codex_negated_approval_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_unapproved_prefix_root_comment_exit_needs_revision" "1" "$_codex_unapproved_prefix_root_comment_exit"
run_test "codex_unapproved_prefix_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_markdown_negated_approval_root_comment_exit_needs_revision" "1" "$_codex_markdown_negated_approval_root_comment_exit"
run_test "codex_markdown_negated_approval_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_qualifier_negated_approval_root_comment_exit_needs_revision" "1" "$_codex_qualifier_negated_approval_root_comment_exit"
run_test "codex_qualifier_negated_approval_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_usage_limit_topic_mention_not_quota_exit_needs_revision" "1" "$_codex_usage_limit_topic_mention_not_quota_exit"
run_test "codex_usage_limit_topic_mention_not_quota_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_negated_no_blocking_issues_root_comment_exit_needs_revision" "1" "$_codex_negated_no_blocking_issues_root_comment_exit"
run_test "codex_negated_no_blocking_issues_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_usage_limit_code_reviews_phrase_mention_exit_needs_revision" "1" "$_codex_usage_limit_code_reviews_phrase_mention_exit"
run_test "codex_usage_limit_code_reviews_phrase_mention_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_negation_beyond_bounded_window_root_comment_exit_needs_revision" "1" "$_codex_negation_beyond_bounded_window_root_comment_exit"
run_test "codex_negation_beyond_bounded_window_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_negation_prior_sentence_does_not_leak_root_comment_exit_needs_revision" "1" "$_codex_negation_prior_sentence_does_not_leak_root_comment_exit"
run_test "codex_negation_prior_sentence_does_not_leak_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_negation_reverse_order_cannot_approve_root_comment_exit_needs_revision" "1" "$_codex_negation_reverse_order_cannot_approve_root_comment_exit"
run_test "codex_negation_reverse_order_cannot_approve_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_terminal_comment_quotes_env_error_not_ancillary_exit_needs_revision" "1" "$_codex_terminal_comment_quotes_env_error_not_ancillary_exit"
run_test "codex_terminal_comment_quotes_env_error_not_ancillary_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_unrelated_later_negation_safe_fails_root_comment_exit_needs_revision" "1" "$_codex_unrelated_later_negation_safe_fails_root_comment_exit"
run_test "codex_unrelated_later_negation_safe_fails_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_quoted_clean_phrase_not_approved_root_comment_exit_needs_revision" "1" "$_codex_quoted_clean_phrase_not_approved_root_comment_exit"
run_test "codex_quoted_clean_phrase_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_semicolon_scoped_negation_root_comment_exit_needs_revision" "1" "$_codex_semicolon_scoped_negation_root_comment_exit"
run_test "codex_semicolon_scoped_negation_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_backtick_quoted_phrase_not_approved_root_comment_exit_needs_revision" "1" "$_codex_backtick_quoted_phrase_not_approved_root_comment_exit"
run_test "codex_backtick_quoted_phrase_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_quoted_rejection_in_clean_review_root_comment_exit_needs_revision" "1" "$_codex_quoted_rejection_in_clean_review_root_comment_exit"
run_test "codex_quoted_rejection_in_clean_review_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_comma_scoped_negation_root_comment_exit_needs_revision" "1" "$_codex_comma_scoped_negation_root_comment_exit"
run_test "codex_comma_scoped_negation_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_terminal_review_quotes_quota_message_exit_needs_revision" "1" "$_codex_terminal_review_quotes_quota_message_exit"
run_test "codex_terminal_review_quotes_quota_message_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_not_only_idiom_safe_fails_root_comment_exit_needs_revision" "1" "$_codex_not_only_idiom_safe_fails_root_comment_exit"
run_test "codex_not_only_idiom_safe_fails_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_not_only_idiom_uppercase_safe_fails_root_comment_exit_needs_revision" "1" "$_codex_not_only_idiom_uppercase_safe_fails_root_comment_exit"
run_test "codex_not_only_idiom_uppercase_safe_fails_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_unable_to_approve_root_comment_exit_needs_revision" "1" "$_codex_unable_to_approve_root_comment_exit"
run_test "codex_unable_to_approve_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_blockquoted_clean_phrase_not_approved_root_comment_exit_needs_revision" "1" "$_codex_blockquoted_clean_phrase_not_approved_root_comment_exit"
run_test "codex_blockquoted_clean_phrase_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_quoted_blocker_token_safe_fails_root_comment_exit_needs_revision" "1" "$_codex_quoted_blocker_token_safe_fails_root_comment_exit"
run_test "codex_quoted_blocker_token_safe_fails_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_fenced_example_outside_blocker_stays_blocking_root_comment_exit_needs_revision" "1" "$_codex_fenced_example_outside_blocker_stays_blocking_root_comment_exit"
run_test "codex_fenced_example_outside_blocker_stays_blocking_root_comment_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_dismissed_review_excluded_root_comment_exit_timed_out" "2" "$_codex_dismissed_review_excluded_root_comment_exit"
run_test "codex_dismissed_review_excluded_root_comment_verdict_not_approved" "TIMED_OUT" \
  "$(printf '%s\n' "$_codex_dismissed_review_excluded_root_comment_output" | grep -oE 'VERDICT: (TIMED_OUT|APPROVED)' | grep -oE 'TIMED_OUT|APPROVED')"
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
run_test "codex_multiline_quoted_clean_phrase_not_approved_root_comment_exit_needs_revision" "1" "$_codex_multiline_quoted_clean_phrase_not_approved_root_comment_exit"
run_test "codex_multiline_quoted_clean_phrase_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_multiline_single_quoted_whole_line_not_approved_root_comment_exit_needs_revision" "1" "$_codex_multiline_single_quoted_whole_line_not_approved_root_comment_exit"
run_test "codex_multiline_single_quoted_whole_line_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_multiline_backtick_span_not_approved_root_comment_exit_needs_revision" "1" "$_codex_multiline_backtick_span_not_approved_root_comment_exit"
run_test "codex_multiline_backtick_span_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_dont_approve_not_approved_root_comment_exit_needs_revision" "1" "$_codex_dont_approve_not_approved_root_comment_exit"
run_test "codex_dont_approve_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_double_backtick_span_not_approved_root_comment_exit_needs_revision" "1" "$_codex_double_backtick_span_not_approved_root_comment_exit"
run_test "codex_double_backtick_span_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_should_not_be_merged_blocking_root_comment_exit_needs_revision" "1" "$_codex_should_not_be_merged_blocking_root_comment_exit"
run_test "codex_should_not_be_merged_blocking_root_comment_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_do_not_merge_blocking_root_comment_exit_needs_revision" "1" "$_codex_do_not_merge_blocking_root_comment_exit"
run_test "codex_do_not_merge_blocking_root_comment_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_cannot_be_merged_blocking_root_comment_exit_needs_revision" "1" "$_codex_cannot_be_merged_blocking_root_comment_exit"
run_test "codex_cannot_be_merged_blocking_root_comment_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_unrelated_negation_before_merge_safe_fails_root_comment_exit_needs_revision" "1" "$_codex_unrelated_negation_before_merge_safe_fails_root_comment_exit"
run_test "codex_unrelated_negation_before_merge_safe_fails_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_shouldnt_be_merged_blocking_root_comment_exit_needs_revision" "1" "$_codex_shouldnt_be_merged_blocking_root_comment_exit"
run_test "codex_shouldnt_be_merged_blocking_root_comment_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_not_only_safe_to_merge_safe_fails_root_comment_exit_needs_revision" "1" "$_codex_not_only_safe_to_merge_safe_fails_root_comment_exit"
run_test "codex_not_only_safe_to_merge_safe_fails_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_wouldnt_approve_not_approved_root_comment_exit_needs_revision" "1" "$_codex_wouldnt_approve_not_approved_root_comment_exit"
run_test "codex_wouldnt_approve_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
  "$(printf '%s\n' "$_codex_wouldnt_approve_not_approved_root_comment_output" | grep "^VERDICT:")"
rm -rf "$_codex_wouldnt_approve_not_approved_root_comment_mock_dir"
unset _codex_wouldnt_approve_not_approved_root_comment_mock_dir _codex_wouldnt_approve_not_approved_root_comment_output _codex_wouldnt_approve_not_approved_root_comment_exit

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
run_test "codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_exit_needs_revision" "1" "$_codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_exit"
run_test "codex_didnt_find_issues_and_looks_good_safe_fails_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_single_quoted_phrase_not_approved_root_comment_exit_needs_revision" "1" "$_codex_single_quoted_phrase_not_approved_root_comment_exit"
run_test "codex_single_quoted_phrase_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_contraction_apostrophes_not_mangled_root_comment_exit_needs_revision" "1" "$_codex_contraction_apostrophes_not_mangled_root_comment_exit"
run_test "codex_contraction_apostrophes_not_mangled_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_fenced_code_block_phrase_not_approved_root_comment_exit_needs_revision" "1" "$_codex_fenced_code_block_phrase_not_approved_root_comment_exit"
run_test "codex_fenced_code_block_phrase_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_nested_fence_length_phrase_not_approved_root_comment_exit_needs_revision" "1" "$_codex_nested_fence_length_phrase_not_approved_root_comment_exit"
run_test "codex_nested_fence_length_phrase_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_fence_close_requires_whitespace_only_root_comment_exit_needs_revision" "1" "$_codex_fence_close_requires_whitespace_only_root_comment_exit"
run_test "codex_fence_close_requires_whitespace_only_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_tilde_fence_phrase_not_approved_root_comment_exit_needs_revision" "1" "$_codex_tilde_fence_phrase_not_approved_root_comment_exit"
run_test "codex_tilde_fence_phrase_not_approved_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_inline_backtick_pair_safe_fails_root_comment_exit_needs_revision" "1" "$_codex_inline_backtick_pair_safe_fails_root_comment_exit"
run_test "codex_inline_backtick_pair_safe_fails_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_fenced_quota_example_not_unavailable_root_comment_exit_needs_revision" "1" "$_codex_fenced_quota_example_not_unavailable_root_comment_exit"
run_test "codex_fenced_quota_example_not_unavailable_root_comment_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_env_error_vs_unrecognized_review_tie_exit_needs_revision" "1" "$_codex_env_error_vs_unrecognized_review_tie_exit"
run_test "codex_env_error_vs_unrecognized_review_tie_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_stale_review_exit_unavailable" "2" "$_codex_stale_review_exit"
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
run_test "codex_stale_inline_exit_unavailable" "2" "$_codex_stale_inline_exit"
if printf '%s\n' "$_codex_stale_inline_output" | grep -q "^VERDICT: NEEDS_REVISION"; then
  _codex_stale_inline_needs_revision="yes"
else
  _codex_stale_inline_needs_revision="no"
fi
run_test "codex_stale_inline_not_needs_revision" "no" "$_codex_stale_inline_needs_revision"
rm -rf "$_codex_stale_inline_mock_dir"
unset _codex_stale_inline_mock_dir _codex_stale_inline_output _codex_stale_inline_exit _codex_stale_inline_needs_revision

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
run_test "codex_cloud_environment_finding_exit_needs_revision" "1" "$_codex_cloud_environment_finding_exit"
run_test "codex_cloud_environment_finding_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_environment_phrase_finding_exit_needs_revision" "1" "$_codex_environment_phrase_finding_exit"
run_test "codex_environment_phrase_finding_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_quoted_environment_finding_exit_needs_revision" "1" "$_codex_quoted_environment_finding_exit"
run_test "codex_quoted_environment_finding_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_final_ack_clean_comment_exit_unavailable" "2" "$_codex_final_ack_clean_comment_exit"
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
run_test "codex_e2_real_pr1490_review_not_approved_exit_needs_revision" "1" "$_codex_e2_real_pr1490_review_not_approved_exit"
run_test "codex_e2_real_pr1490_review_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e3_missing_swish_not_approved_exit_needs_revision" "1" "$_codex_e3_missing_swish_not_approved_exit"
run_test "codex_e3_missing_swish_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e5_short_sha_not_approved_exit_needs_revision" "1" "$_codex_e5_short_sha_not_approved_exit"
run_test "codex_e5_short_sha_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e6_oversized_sha_not_approved_exit_needs_revision" "1" "$_codex_e6_oversized_sha_not_approved_exit"
run_test "codex_e6_oversized_sha_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e8_non_hex_sha_not_approved_exit_needs_revision" "1" "$_codex_e8_non_hex_sha_not_approved_exit"
run_test "codex_e8_non_hex_sha_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e9_leading_prose_not_approved_exit_needs_revision" "1" "$_codex_e9_leading_prose_not_approved_exit"
run_test "codex_e9_leading_prose_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e10_trailing_prose_not_approved_exit_needs_revision" "1" "$_codex_e10_trailing_prose_not_approved_exit"
run_test "codex_e10_trailing_prose_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e11_fenced_wrapper_not_approved_exit_needs_revision" "1" "$_codex_e11_fenced_wrapper_not_approved_exit"
run_test "codex_e11_fenced_wrapper_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e13_case_altered_not_approved_exit_needs_revision" "1" "$_codex_e13_case_altered_not_approved_exit"
run_test "codex_e13_case_altered_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e15_underscore_variant_not_approved_exit_needs_revision" "1" "$_codex_e15_underscore_variant_not_approved_exit"
run_test "codex_e15_underscore_variant_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e16_disqualifier_gap_not_approved_exit_needs_revision" "1" "$_codex_e16_disqualifier_gap_not_approved_exit"
run_test "codex_e16_disqualifier_gap_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e17_zero_tolerance_gap_not_approved_exit_needs_revision" "1" "$_codex_e17_zero_tolerance_gap_not_approved_exit"
run_test "codex_e17_zero_tolerance_gap_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e18_vendor_flavor_token_gap_not_approved_exit_needs_revision" "1" "$_codex_e18_vendor_flavor_token_gap_not_approved_exit"
run_test "codex_e18_vendor_flavor_token_gap_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e19_non_vendor_details_block_not_approved_exit_needs_revision" "1" "$_codex_e19_non_vendor_details_block_not_approved_exit"
run_test "codex_e19_non_vendor_details_block_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e20_tag_flexible_variant_not_approved_exit_needs_revision" "1" "$_codex_e20_tag_flexible_variant_not_approved_exit"
run_test "codex_e20_tag_flexible_variant_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e21_filler_composed_hedge_not_approved_exit_needs_revision" "1" "$_codex_e21_filler_composed_hedge_not_approved_exit"
run_test "codex_e21_filler_composed_hedge_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e22_refusal_inside_footer_blocking_exit_needs_revision" "1" "$_codex_e22_refusal_inside_footer_blocking_exit"
run_test "codex_e22_refusal_inside_footer_blocking_verdict" "VERDICT: NEEDS_REVISION" \
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
run_test "codex_e23_footer_opening_line_only_not_approved_exit_needs_revision" "1" "$_codex_e23_footer_opening_line_only_not_approved_exit"
run_test "codex_e23_footer_opening_line_only_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e24a_footer_byte_mutation_mid_sentence_not_approved_exit_needs_revision" "1" "$_codex_e24a_footer_byte_mutation_mid_sentence_not_approved_exit"
run_test "codex_e24a_footer_byte_mutation_mid_sentence_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e24b_footer_byte_mutation_before_details_close_not_approved_exit_needs_revision" "1" "$_codex_e24b_footer_byte_mutation_before_details_close_not_approved_exit"
run_test "codex_e24b_footer_byte_mutation_before_details_close_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_e24c_footer_byte_mutation_in_url_not_approved_exit_needs_revision" "1" "$_codex_e24c_footer_byte_mutation_in_url_not_approved_exit"
run_test "codex_e24c_footer_byte_mutation_in_url_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_footer_near_miss_main_loop_safe_fails_exit_needs_revision" "1" "$_codex_footer_near_miss_main_loop_safe_fails_exit"
run_test "codex_footer_near_miss_main_loop_safe_fails_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_footer_near_miss_async_arrival_safe_fails_exit_needs_revision" "1" "$_codex_footer_near_miss_async_arrival_safe_fails_exit"
run_test "codex_footer_near_miss_async_arrival_safe_fails_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_footer_near_miss_async_final_safe_fails_exit_needs_revision" "1" "$_codex_footer_near_miss_async_final_safe_fails_exit"
run_test "codex_footer_near_miss_async_final_safe_fails_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_footer_near_miss_async_reaction_final_safe_fails_exit_needs_revision" "1" "$_codex_footer_near_miss_async_reaction_final_safe_fails_exit"
run_test "codex_footer_near_miss_async_reaction_final_safe_fails_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_placeholder_exceeds_length_cap_not_approved_exit_needs_revision" "1" "$_codex_placeholder_exceeds_length_cap_not_approved_exit"
run_test "codex_placeholder_exceeds_length_cap_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_placeholder_asterisk_not_approved_exit_needs_revision" "1" "$_codex_placeholder_asterisk_not_approved_exit"
run_test "codex_placeholder_asterisk_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_placeholder_backtick_not_approved_exit_needs_revision" "1" "$_codex_placeholder_backtick_not_approved_exit"
run_test "codex_placeholder_backtick_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
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
run_test "codex_placeholder_newline_separated_overflow_not_approved_exit_needs_revision" "1" "$_codex_placeholder_newline_separated_overflow_not_approved_exit"
run_test "codex_placeholder_newline_separated_overflow_not_approved_verdict" "VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)" \
  "$(printf '%s\n' "$_codex_placeholder_newline_separated_overflow_not_approved_output" | grep "^VERDICT:")"
rm -rf "$_codex_placeholder_newline_separated_overflow_not_approved_mock_dir"
unset _codex_placeholder_newline_separated_overflow_not_approved_mock_dir _codex_placeholder_newline_separated_overflow_not_approved_output _codex_placeholder_newline_separated_overflow_not_approved_exit



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
# Area: CodeRabbit "Review skipped" banner is not review activity (issue #1531)
#
# CodeRabbit posts a "Review skipped" banner instead of a review whenever it
# declines by configuration rather than by capacity (auto_review.enabled false,
# drafts excluded, or base_branches not matching the PR base). Before this fix
# the activity probe in run_coderabbit_review excluded only the pause,
# rate-limit, and resume markers, so the skip banner read as "CodeRabbit posted
# something", broke the poll loop into Phase 3, and Phase 3 returned
# RESULT=clean after collecting zero inline comments — a clean verdict on a PR
# CodeRabbit never looked at.
#
# The end-to-end case runs with poll_interval=1, max_wait=3 and
# CODERABBIT_NO_TRIGGER_TIMEOUT=1 so the loop exercises the explicit-nudge path
# and then its timeout branch — where the skip-banner guard lives — within a few
# seconds of real sleep.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area: CodeRabbit skip-banner false-clean (issue #1531) ==="

unset MOCK_GH_OUTPUT MOCK_GH_POST_EXIT MOCK_GH_POST_OUTPUT MOCK_GH_CALL_LOG MOCK_GH_EXIT

# The exact banner CodeRabbit posts when reviews.auto_review.enabled is false,
# quoted from an observed comment on this repository (PR #1527).
_CR_SKIP_BANNER_1531='<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!IMPORTANT]\n> ## Review skipped\n> \n> Auto reviews are disabled on this repository. Please check the settings in the CodeRabbit UI or the `.coderabbit.yaml` file in this repository. To trigger a single review, invoke the `@coderabbitai review` command.'

# --- AC-1: the regex classifies banners, not genuine reviews ------------------
_cr_re_matches_1531() {
  printf '%s' "$1" \
    | jq -Rs --arg skip_re "$CODERABBIT_SKIP_BANNER_RE" \
        'if test($skip_re; "i") then "yes" else "no" end' -r
}

run_test "cr_skip_banner_re_matches_auto_reviews_disabled" "yes" \
  "$(_cr_re_matches_1531 "$_CR_SKIP_BANNER_1531")"

# The "Review skipped" half must match on its own: CodeRabbit uses the same
# heading for the drafts-excluded and base-branch-mismatch variants, whose
# bodies never contain the "auto reviews are disabled" sentence.
run_test "cr_skip_banner_re_matches_review_skipped_alone" "yes" \
  "$(_cr_re_matches_1531 '> [!IMPORTANT]
> ## Review skipped
>
> Draft detected. Set `reviews.auto_review.drafts` to true to review draft PRs.')"

# CONTROL: a BARE "## Review skipped" heading, with no blockquote prefix, is not
# a banner. A genuine CodeRabbit comment may legitimately use that heading, and
# classifying it as a banner would drop a real review from the activity probe.
run_test "cr_skip_banner_re_ignores_bare_heading" "no" \
  "$(_cr_re_matches_1531 '## Review skipped

This section explains when the reviewer skips generated files.')"

# CONTROL: a genuine CodeRabbit walkthrough must NOT match, or the fix would
# suppress real reviews and hang every loop until timeout.
run_test "cr_skip_banner_re_ignores_genuine_walkthrough" "no" \
  "$(_cr_re_matches_1531 '## Walkthrough

The changes update the reviewer loop. Estimated code review effort: 3.')"

# CONTROL: the word "skipped" in ordinary review prose must not match either.
run_test "cr_skip_banner_re_ignores_prose_use_of_skipped" "no" \
  "$(_cr_re_matches_1531 'Nitpick: this branch is skipped when the list is empty.')"

# CONTROL, and the reason the pattern is not a bare "review skipped" substring:
# a genuine walkthrough may use that exact phrase in prose. Matching it would be
# the mirror-image failure — a real review classified as a banner, ignored by the
# activity probe, polled to timeout, and escalated.
run_test "cr_skip_banner_re_ignores_exact_phrase_in_prose" "no" \
  "$(_cr_re_matches_1531 'The walkthrough notes that this review skipped the generated files.')"

# The HTML marker CodeRabbit stamps on skip comments (and on no other kind) is
# the most reliable signal, and must match on its own even if the rendered
# heading text is reworded by the vendor.
run_test "cr_skip_banner_re_matches_html_marker_alone" "yes" \
  "$(_cr_re_matches_1531 '<!-- This is an auto-generated comment: skip review by coderabbit.ai -->')"

# The pattern is consumed by BOTH jq (test(); Oniguruma) and grep -qiE (POSIX
# ERE). A pattern valid in only one engine would silently stop matching at one of
# the two call sites, so the engines are asserted to agree.
_cr_grep_matches_1531() {
  if printf '%s' "$1" | grep -qiE "$CODERABBIT_SKIP_BANNER_RE"; then echo yes; else echo no; fi
}
run_test "cr_skip_banner_re_grep_agrees_on_banner" "yes" \
  "$(_cr_grep_matches_1531 '> ## Review skipped')"
run_test "cr_skip_banner_re_grep_agrees_on_bare_heading" "no" \
  "$(_cr_grep_matches_1531 '## Review skipped')"
run_test "cr_skip_banner_re_grep_agrees_on_prose" "no" \
  "$(_cr_grep_matches_1531 'The walkthrough notes that this review skipped the generated files.')"

# --- AC-1: the activity probe returns 0 for a banner-only comment set ---------
# Mirrors the production jq expression in run_coderabbit_review so a future edit
# that drops the $skip_re clause is caught here.
_cr_activity_count_1531() {
  printf '%s' "$1" \
    | jq -s --arg bot "coderabbitai[bot]" --arg since "2020-01-01T00:00:00Z" \
         --arg skip_re "$CODERABBIT_SKIP_BANNER_RE" '
        [.[].[] | select(
            .user.login == $bot and
            .created_at > $since and
            ((.body // "") | test("Reviews paused|review paused"; "i") | not) and
            ((.body // "") | test("rate.?limit"; "i") | not) and
            ((.body // "") | test("reviews resumed"; "i") | not) and
            ((.body // "") | test($skip_re; "i") | not)
        )] | length
      '
}

run_test "cr_activity_probe_skip_banner_not_activity" "0" \
  "$(_cr_activity_count_1531 "$(jq -cn --arg b "$_CR_SKIP_BANNER_1531" \
       '[{user:{login:"coderabbitai[bot]"},created_at:"2020-01-01T00:00:01Z",body:$b}]')")"

run_test "cr_activity_probe_genuine_review_is_activity" "1" \
  "$(_cr_activity_count_1531 "$(jq -cn \
       '[{user:{login:"coderabbitai[bot]"},created_at:"2020-01-01T00:00:01Z",body:"## Walkthrough\n\nLGTM."}]')")"

# --- AC-2 / AC-3: end-to-end escalation instead of a clean verdict ------------
_cr_mock_dir_1531="$(mktemp -d)"
_cr_call_log_1531="$_cr_mock_dir_1531/calls.log"
cat > "$_cr_mock_dir_1531/gh" <<'CR_GH_1531'
#!/usr/bin/env bash
# Strict mock: every gh invocation run_coderabbit_review legitimately makes is
# enumerated, and anything else is a hard error. A permissive "*) echo []" fallback
# would let these cases pass for the wrong reason — a renamed or dropped comments
# request would silently return an empty array and still produce the expected
# REASON, proving nothing.
printf '%s\n' "$*" >> "$CR_CALL_LOG"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'abc1531sha\n'; exit 0 ;;
  *"commits/abc1531sha --jq .commit.committer.date"*) printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1531sha/statuses"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '%s\n' '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:01Z","updated_at":"2020-01-01T00:00:01Z","body":"<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!IMPORTANT]\n> ## Review skipped\n>\n> Auto reviews are disabled on this repository."}]'
    exit 0 ;;
  *"api graphql"*)
    printf '%s\n' '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}'
    exit 0 ;;
  *"pr comment 42"*) exit 0 ;;
  *)
    printf 'UNEXPECTED gh invocation in 1531 mock: %s\n' "$*" >&2
    exit 1 ;;
esac
CR_GH_1531
chmod +x "$_cr_mock_dir_1531/gh"

actual_output="$(
  PATH="$_cr_mock_dir_1531:$PATH" CR_CALL_LOG="$_cr_call_log_1531" \
    CODERABBIT_NO_TRIGGER_TIMEOUT=1 \
    run_coderabbit_review "42" "fix/42-test" "1" "3" 2>/dev/null || true
)"

# The planted violation: before the fix this asserted RESULT=clean.
run_test "cr_skip_banner_escalates_not_clean" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"

# A distinct REASON from rate_limit_max_retries — the operator fix is a
# .coderabbit.yaml change, not waiting out a vendor quota.
run_test "cr_skip_banner_reason_is_review_skipped_banner" "REASON=review_skipped_banner" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"

# The mock errors on any unenumerated call, but silence is not proof the RIGHT
# call happened — assert the comments endpoint was actually requested.
run_test "cr_skip_banner_queried_issue_comments" "yes" \
  "$([ "$(grep_count_or_zero "issues/42/comments" "$_cr_call_log_1531")" -ge 1 ] && echo yes || echo no)"

# AC-2: the loop must still have nudged CodeRabbit with an explicit trigger
# before giving up, since "@coderabbitai review" works even when auto review is
# disabled. Without the activity-probe fix the loop broke out immediately and
# never reached the retrigger path.
_cr_trigger_count_1531="$(grep_count_or_zero "pr comment 42 --body @coderabbitai review" "$_cr_call_log_1531")"
run_test "cr_skip_banner_posts_explicit_review_trigger" "yes" \
  "$([ "$_cr_trigger_count_1531" -ge 1 ] && echo yes || echo no)"

# The nudge must stay bounded by CODERABBIT_RATE_LIMIT_MAX_RETRIES rather than
# firing on every poll iteration — an unbounded nudge would spam the PR and burn
# vendor quota on a PR CodeRabbit is configured never to review.
run_test "cr_skip_banner_trigger_is_capped" "yes" \
  "$([ "$_cr_trigger_count_1531" -le 4 ] && echo yes || echo no)"
unset _cr_trigger_count_1531

rm -rf "$_cr_mock_dir_1531"
unset _cr_mock_dir_1531 _cr_call_log_1531 actual_output _CR_SKIP_BANNER_1531

# --- Stale draft banner must not shadow a newer, more specific outcome --------
# A repository that runs coderabbit in on_ready.github keeps auto_review.drafts
# false, so EVERY PR collects a "Review skipped / Draft detected" banner while it
# is still a draft. That banner is newer than the HEAD commit, so a guard that
# matched any banner inside the since_iso window would blame it for every later
# ready-phase timeout. Here the newest CodeRabbit comment is a rate-limit notice:
# the run must escalate as rate_limit_max_retries, not review_skipped_banner.
_cr_mock_dir_1531b="$(mktemp -d)"
_cr_call_log_1531b="$_cr_mock_dir_1531b/calls.log"
cat > "$_cr_mock_dir_1531b/gh" <<'CR_GH_1531B'
#!/usr/bin/env bash
# Strict mock: every gh invocation run_coderabbit_review legitimately makes is
# enumerated, and anything else is a hard error. A permissive "*) echo []" fallback
# would let these cases pass for the wrong reason — a renamed or dropped comments
# request would silently return an empty array and still produce the expected
# REASON, proving nothing.
printf '%s\n' "$*" >> "$CR_CALL_LOG"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'abc1531bsha\n'; exit 0 ;;
  *"commits/abc1531bsha --jq .commit.committer.date"*) printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1531bsha/statuses"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '%s\n' '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:01Z","updated_at":"2020-01-01T00:00:01Z","body":"<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!IMPORTANT]\n> ## Review skipped\n>\n> Draft detected."},{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:05:00Z","updated_at":"2020-01-01T00:05:00Z","body":"Review limit reached — rate limit in effect."}]'
    exit 0 ;;
  *"api graphql"*)
    printf '%s\n' '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}'
    exit 0 ;;
  *"pr comment 42"*) exit 0 ;;
  *)
    printf 'UNEXPECTED gh invocation in 1531B mock: %s\n' "$*" >&2
    exit 1 ;;
esac
CR_GH_1531B
chmod +x "$_cr_mock_dir_1531b/gh"

actual_output="$(
  PATH="$_cr_mock_dir_1531b:$PATH" CR_CALL_LOG="$_cr_call_log_1531b" \
    CODERABBIT_NO_TRIGGER_TIMEOUT=1 CODERABBIT_RATE_LIMIT_WAIT=1 \
    CODERABBIT_RATE_LIMIT_MAX_RETRIES=1 \
    run_coderabbit_review "42" "fix/42-test" "1" "3" 2>/dev/null || true
)"

run_test "cr_stale_draft_banner_does_not_shadow_rate_limit" "REASON=rate_limit_max_retries" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "cr_stale_draft_banner_still_escalates" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "cr_stale_draft_banner_queried_issue_comments" "yes" \
  "$([ "$(grep_count_or_zero "issues/42/comments" "$_cr_call_log_1531b")" -ge 1 ] && echo yes || echo no)"

rm -rf "$_cr_mock_dir_1531b"
unset _cr_mock_dir_1531b _cr_call_log_1531b actual_output

# --- A banner from a PREVIOUS HEAD must not be attributed to this one --------
# Mirror of the stale-draft case above. Here the only CodeRabbit comment is a
# skip banner that PREDATES the HEAD commit — the shape produced by pushing a
# new commit after a draft-phase banner. CodeRabbit has said nothing about the
# current HEAD, so the outcome is "did not review this HEAD" (no_review), not a
# configuration problem. Reporting review_skipped_banner here would send the
# operator to .coderabbit.yaml for what is really a silent or rate-limited review.
_cr_mock_dir_1531c="$(mktemp -d)"
_cr_call_log_1531c="$_cr_mock_dir_1531c/calls.log"
cat > "$_cr_mock_dir_1531c/gh" <<'CR_GH_1531C'
#!/usr/bin/env bash
# Strict mock: every gh invocation run_coderabbit_review legitimately makes is
# enumerated, and anything else is a hard error. A permissive "*) echo []" fallback
# would let these cases pass for the wrong reason — a renamed or dropped comments
# request would silently return an empty array and still produce the expected
# REASON, proving nothing.
printf '%s\n' "$*" >> "$CR_CALL_LOG"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'abc1531csha\n'; exit 0 ;;
  *"commits/abc1531csha --jq .commit.committer.date"*) printf '2020-01-02T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1531csha/statuses"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '%s\n' '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:01Z","updated_at":"2020-01-01T00:00:01Z","body":"<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!IMPORTANT]\n> ## Review skipped\n>\n> Draft detected."}]'
    exit 0 ;;
  *"api graphql"*)
    printf '%s\n' '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}'
    exit 0 ;;
  *"pr comment 42"*) exit 0 ;;
  *)
    printf 'UNEXPECTED gh invocation in 1531C mock: %s\n' "$*" >&2
    exit 1 ;;
esac
CR_GH_1531C
chmod +x "$_cr_mock_dir_1531c/gh"

actual_output="$(
  PATH="$_cr_mock_dir_1531c:$PATH" CR_CALL_LOG="$_cr_call_log_1531c" \
    CODERABBIT_NO_TRIGGER_TIMEOUT=1 \
    run_coderabbit_review "42" "fix/42-test" "1" "3" 2>/dev/null || true
)"

run_test "cr_banner_from_previous_head_not_attributed" "REASON=no_review" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "cr_banner_from_previous_head_queried_issue_comments" "yes" \
  "$([ "$(grep_count_or_zero "issues/42/comments" "$_cr_call_log_1531c")" -ge 1 ] && echo yes || echo no)"

rm -rf "$_cr_mock_dir_1531c"
unset _cr_mock_dir_1531c _cr_call_log_1531c actual_output

# --- The "latest" comment is ordered by EFFECTIVE event time -----------------
# Admitting comments on `updated_at` and then ordering them on `created_at`
# contradicts itself: an older comment CodeRabbit edited a moment ago is the most
# recent thing it said, but a created_at sort ranks anything posted in between
# above it. Both permutations below are non-activity comments (a skip banner and
# a rate-limit notice), so both reach the timeout guard, and each one flips its
# verdict if the sort key regresses to created_at.

# Permutation 1 — banner created last, rate-limit notice UPDATED last.
# Effective latest is the rate-limit notice, so this is a quota problem.
_cr_mock_dir_1531d="$(mktemp -d)"
_cr_call_log_1531d="$_cr_mock_dir_1531d/calls.log"
cat > "$_cr_mock_dir_1531d/gh" <<'CR_GH_1531D'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CR_CALL_LOG"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'abc1531dsha\n'; exit 0 ;;
  *"commits/abc1531dsha --jq .commit.committer.date"*) printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1531dsha/statuses"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '%s\n' '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:30Z","updated_at":"2020-01-01T00:00:30Z","body":"<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!IMPORTANT]\n> ## Review skipped\n>\n> Draft detected."},{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:10Z","updated_at":"2020-01-01T00:01:00Z","body":"Review limit reached — rate limit in effect."}]'
    exit 0 ;;
  *"api graphql"*)
    printf '%s\n' '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}'
    exit 0 ;;
  *"pr comment 42"*) exit 0 ;;
  *)
    printf 'UNEXPECTED gh invocation in abc1531d mock: %s\n' "$*" >&2
    exit 1 ;;
esac
CR_GH_1531D
chmod +x "$_cr_mock_dir_1531d/gh"

actual_output="$(
  PATH="$_cr_mock_dir_1531d:$PATH" CR_CALL_LOG="$_cr_call_log_1531d" \
    CODERABBIT_NO_TRIGGER_TIMEOUT=1 CODERABBIT_RATE_LIMIT_WAIT=1 \
    CODERABBIT_RATE_LIMIT_MAX_RETRIES=1 \
    run_coderabbit_review "42" "fix/42-test" "1" "3" 2>/dev/null || true
)"
run_test "cr_latest_by_effective_time_prefers_updated_rate_limit" "REASON=rate_limit_max_retries" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
rm -rf "$_cr_mock_dir_1531d"
unset _cr_mock_dir_1531d _cr_call_log_1531d actual_output

# Permutation 2 — rate-limit notice created last, banner UPDATED last.
# Effective latest is the banner, so this is a configuration problem.
_cr_mock_dir_1531e="$(mktemp -d)"
_cr_call_log_1531e="$_cr_mock_dir_1531e/calls.log"
cat > "$_cr_mock_dir_1531e/gh" <<'CR_GH_1531E'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CR_CALL_LOG"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'abc1531esha\n'; exit 0 ;;
  *"commits/abc1531esha --jq .commit.committer.date"*) printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1531esha/statuses"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '%s\n' '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:30Z","updated_at":"2020-01-01T00:00:30Z","body":"Review limit reached — rate limit in effect."},{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:10Z","updated_at":"2020-01-01T00:01:00Z","body":"<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!IMPORTANT]\n> ## Review skipped\n>\n> Draft detected."}]'
    exit 0 ;;
  *"api graphql"*)
    printf '%s\n' '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}'
    exit 0 ;;
  *"pr comment 42"*) exit 0 ;;
  *)
    printf 'UNEXPECTED gh invocation in abc1531e mock: %s\n' "$*" >&2
    exit 1 ;;
esac
CR_GH_1531E
chmod +x "$_cr_mock_dir_1531e/gh"

actual_output="$(
  PATH="$_cr_mock_dir_1531e:$PATH" CR_CALL_LOG="$_cr_call_log_1531e" \
    CODERABBIT_NO_TRIGGER_TIMEOUT=1 CODERABBIT_RATE_LIMIT_WAIT=1 \
    CODERABBIT_RATE_LIMIT_MAX_RETRIES=1 \
    run_coderabbit_review "42" "fix/42-test" "1" "3" 2>/dev/null || true
)"
run_test "cr_latest_by_effective_time_prefers_updated_banner" "REASON=review_skipped_banner" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
rm -rf "$_cr_mock_dir_1531e"
unset _cr_mock_dir_1531e _cr_call_log_1531e actual_output

# --- AC-4: rate-limit tolerance spans an hourly vendor quota reset ------------
# Asserted against the script source: the whole point of the change is that the
# shipped numbers (not just the env overrides) are large enough.
#
# These greps used to target the inline "${VAR:-4}" / "${VAR:-900}" expansions
# inside run_coderabbit_review. Issue #1562 gave the same two numbers a second
# reader — the execution-budget invariant — so they were hoisted to a single
# declaration rather than restated, which is what these now pin.
run_test "cr_rate_limit_default_retries_is_four" "1" \
  "$(grep_count_or_zero 'CODERABBIT_RATE_LIMIT_MAX_RETRIES_DEFAULT=4' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
run_test "cr_rate_limit_default_wait_is_900" "1" \
  "$(grep_count_or_zero 'CODERABBIT_RATE_LIMIT_WAIT_DEFAULT=900' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
# And the review path must actually consume that declaration, so hoisting the
# numbers out cannot leave the wait reading a stale literal.
run_test "cr_rate_limit_review_path_uses_default_consts" "2" \
  "$(grep_count_or_zero 'CODERABBIT_RATE_LIMIT_MAX_RETRIES:-$CODERABBIT_RATE_LIMIT_MAX_RETRIES_DEFAULT' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"

# ---------------------------------------------------------------------------
# Area 18: suite ergonomics and execution budget (issue #1562)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 18: suite ergonomics and execution budget (#1562) ==="

_1562_suite="$REPO_ROOT/scripts/development-workflow/tests/test-pr-review-loop.sh"
_1562_loop="$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

# --- AC-1: a single area can be run without the full suite -------------------
run_test "area_filter_list_areas_lists_this_area" "yes" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1562_suite" --list-areas 2>/dev/null | grep -q 'Area 18:' && echo yes || echo no)"

_1562_filtered="$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1562_suite" --area 1 2>/dev/null || true)"
run_test "area_filter_runs_selected_area" "yes" \
  "$(printf '%s\n' "$_1562_filtered" | grep -q 'normalize_platform_verdict' && echo yes || echo no)"
# The point of the filter: Area 13 is ~94% of the runtime, so it must be absent.
run_test "area_filter_excludes_other_areas" "yes" \
  "$(printf '%s\n' "$_1562_filtered" | grep -q 'PR #801 reviewer-loop failure paths' && echo no || echo yes)"
# The summary footer carries the exit status and must survive every filter.
run_test "area_filter_keeps_summary_footer" "yes" \
  "$(printf '%s\n' "$_1562_filtered" | grep -q '^Tests: ' && echo yes || echo no)"

run_test "area_filter_unknown_area_exits_2" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1562_suite" --area definitely-not-an-area >/dev/null 2>&1; echo $?)"
run_test "area_filter_missing_value_exits_2" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1562_suite" --area >/dev/null 2>&1; echo $?)"
run_test "area_filter_unknown_flag_exits_2" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" bash "$_1562_suite" --not-a-flag >/dev/null 2>&1; echo $?)"
# A bare number selects that area exactly, not every area containing the digit.
run_test "area_filter_bare_number_is_exact" "yes" \
  "$(printf '%s\n' "$_1562_filtered" | grep -q 'max_cycles' && echo no || echo yes)"

# --- AC-2: a mid-run edit cannot silently alter the result -------------------
run_test "suite_reexecs_from_snapshot" "yes" \
  "$(grep -q 'TEST_PR_REVIEW_LOOP_SNAPSHOT' "$_1562_suite" && echo yes || echo no)"
run_test "suite_snapshot_preserves_origin_for_repo_root" "yes" \
  "$(grep -q 'TEST_PR_REVIEW_LOOP_ORIGIN' "$_1562_suite" && echo yes || echo no)"
# The snapshot must be what actually runs. This process IS a snapshot run, so
# $0 is the temp copy rather than the checked-in path — which is also what
# makes running the harness from outside the repo work, since repo-root
# resolution follows TEST_PR_REVIEW_LOOP_ORIGIN instead of $0.
run_test "suite_runs_from_a_copy_not_the_original" "yes" \
  "$([ "$0" != "$_1562_suite" ] && echo yes || echo no)"
run_test "suite_origin_points_at_the_checked_in_file" "yes" \
  "$([ "${TEST_PR_REVIEW_LOOP_ORIGIN:-}" = "$_1562_suite" ] && echo yes || echo no)"
run_test "suite_repo_root_resolved_despite_snapshot" "yes" \
  "$([ -d "$REPO_ROOT/scripts/development-workflow" ] && echo yes || echo no)"
# Issue #1562 consequence 3: an out-of-tree copy used to fail with "fatal: not
# a git repository" because the root was resolved from the copy's location.
# A pre-set origin now makes that work.
_1562_copy="$(mktemp -t test-pr-review-loop-copy.XXXXXX)"
cat "$_1562_suite" > "$_1562_copy"
run_test "out_of_tree_copy_resolves_repo_root" "yes" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" \
      TEST_PR_REVIEW_LOOP_ORIGIN="$_1562_suite" \
      bash "$_1562_copy" --area 1 2>/dev/null | grep -q '^Tests: ' && echo yes || echo no)"
run_test "out_of_tree_copy_bad_origin_exits_2" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" \
      TEST_PR_REVIEW_LOOP_ORIGIN=/nonexistent/suite.sh \
      bash "$_1562_copy" --area 1 >/dev/null 2>&1; echo $?)"
rm -f "$_1562_copy"
unset _1562_copy

# --- AC-3: a truncated run is never mistaken for a clean one ----------------
run_test "truncation_guard_defined" "yes" \
  "$(type -t _emit_truncation_guard >/dev/null 2>&1 && echo yes || echo no)"

# With no RESULT emitted, the guard supplies a terminal one and forces non-zero.
_RESULT_EMITTED=0
run_test "truncation_guard_forces_nonzero_from_success" "2" \
  "$(_emit_truncation_guard 0 >/dev/null 2>&1; echo $?)"
_RESULT_EMITTED=0
run_test "truncation_guard_emits_result_escalate" "RESULT=escalate" \
  "$(_emit_truncation_guard 0 2>/dev/null | grep '^RESULT=' || true)"
_RESULT_EMITTED=0
run_test "truncation_guard_emits_truncated_reason" "REASON=truncated_run" \
  "$(_emit_truncation_guard 0 2>/dev/null | grep '^REASON=' || true)"
_RESULT_EMITTED=0
run_test "truncation_guard_preserves_kill_status" "143" \
  "$(_emit_truncation_guard 143 >/dev/null 2>&1; echo $?)"

# When a verdict was reached, the guard must not add a second RESULT line.
_RESULT_EMITTED=1
run_test "truncation_guard_silent_after_a_verdict" "" \
  "$(_emit_truncation_guard 0 2>/dev/null | grep '^RESULT=' || true)"
_RESULT_EMITTED=1
run_test "truncation_guard_passes_status_through" "1" \
  "$(_emit_truncation_guard 1 >/dev/null 2>&1; echo $?)"

# print_kv is the choke point that sets the flag, covering all emission sites.
_RESULT_EMITTED=0
print_kv RESULT clean >/dev/null
run_test "print_kv_records_result_emission" "1" "$_RESULT_EMITTED"
_RESULT_EMITTED=0
print_kv REASON something >/dev/null
run_test "print_kv_ignores_non_result_keys" "0" "$_RESULT_EMITTED"
_RESULT_EMITTED=0

# --- AC-4: rate-limit ceiling reconciled with the execution budget ----------
run_test "budget_check_defined" "yes" \
  "$(type -t _check_execution_budget >/dev/null 2>&1 && echo yes || echo no)"

# Shipped defaults must satisfy the invariant: 4 x 900 = 3600 < 5400.
run_test "budget_defaults_satisfy_invariant" "BUDGET_INVARIANT=ok" \
  "$(_check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_default_worst_case_is_3600" "BUDGET_WORST_CASE_RATE_LIMIT_WAIT_SECONDS=3600" \
  "$(_check_execution_budget 2>/dev/null | grep '^BUDGET_WORST_CASE' || true)"
run_test "budget_default_budget_is_5400" "BUDGET_EXECUTION_SECONDS=5400" \
  "$(_check_execution_budget 2>/dev/null | grep '^BUDGET_EXECUTION_SECONDS=' || true)"
run_test "budget_defaults_exit_zero" "0" \
  "$(_check_execution_budget >/dev/null 2>&1; echo $?)"

# A budget below the worst-case wait is a configuration error, reported before
# any waiting rather than discovered as a truncated run an hour later.
run_test "budget_too_small_is_violation" "BUDGET_INVARIANT=violated" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=600 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_too_small_exits_nonzero" "1" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=600 _check_execution_budget >/dev/null 2>&1; echo $?)"
run_test "budget_too_small_escalates" "REASON=execution_budget_misconfigured" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=600 _check_execution_budget 2>/dev/null | grep '^REASON=' || true)"
# Equality is a violation too: the wait must fit strictly inside the budget.
run_test "budget_equal_to_worst_case_is_violation" "BUDGET_INVARIANT=violated" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=3600 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
# Raising the retries without raising the budget is caught.
run_test "budget_raised_retries_violates" "BUDGET_INVARIANT=violated" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=8 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
# Lowering the ceiling to match a tighter budget is the supported escape hatch.
run_test "budget_lowered_ceiling_is_ok" "BUDGET_INVARIANT=ok" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=600 CODERABBIT_RATE_LIMIT_MAX_RETRIES=1 \
     CODERABBIT_RATE_LIMIT_WAIT=300 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
# Non-numeric input falls back to the shipped defaults rather than doing
# arithmetic on a string.
run_test "budget_non_numeric_retries_falls_back" "BUDGET_INVARIANT=ok" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=abc _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_non_numeric_wait_falls_back" "BUDGET_INVARIANT=ok" \
  "$(CODERABBIT_RATE_LIMIT_WAIT=abc _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_non_numeric_budget_falls_back" "BUDGET_INVARIANT=ok" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=abc _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"

# Zero-padded values pass the all-digit guards, and bash reads a leading-zero
# operand inside $(( )) as octal. Before the 10# prefix these crashed the check
# that exists to replace a crash with a clean escalation.
run_test "budget_octal_retries_does_not_crash" "BUDGET_INVARIANT=violated" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=08 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_octal_retries_no_arith_error" "" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=08 _check_execution_budget 2>&1 >/dev/null | grep 'error token' || true)"
run_test "budget_octal_wait_is_base_10" "BUDGET_WORST_CASE_RATE_LIMIT_WAIT_SECONDS=3600" \
  "$(CODERABBIT_RATE_LIMIT_WAIT=0900 _check_execution_budget 2>/dev/null | grep '^BUDGET_WORST_CASE' || true)"
run_test "budget_octal_budget_is_base_10" "BUDGET_EXECUTION_SECONDS=9000" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=09000 _check_execution_budget 2>/dev/null | grep '^BUDGET_EXECUTION_SECONDS=' || true)"

# Oversized digit strings wrap 64-bit arithmetic. retries=99999999999999999
# multiplied out NEGATIVE, which compared as under budget and reported the
# invariant satisfied — the check accepting the unsafe configuration it exists
# to reject. Bounds are enforced before any arithmetic now.
run_test "budget_overflow_retries_rejected" "BUDGET_INVARIANT=violated" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=99999999999999999 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_overflow_retries_not_negative" "" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=99999999999999999 _check_execution_budget 2>/dev/null | grep -- '-[0-9]' || true)"
run_test "budget_overflow_huge_digit_string_rejected" "BUDGET_INVARIANT=violated" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=999999999999999999999 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_overflow_wait_rejected" "BUDGET_INVARIANT=violated" \
  "$(CODERABBIT_RATE_LIMIT_WAIT=99999999999999999 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_overflow_budget_rejected" "BUDGET_INVARIANT=violated" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=99999999999999999 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"
run_test "budget_overflow_escalates" "REASON=execution_budget_misconfigured" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=99999999999999999 _check_execution_budget 2>/dev/null | grep '^REASON=' || true)"
run_test "budget_overflow_exits_nonzero" "1" \
  "$(CODERABBIT_RATE_LIMIT_MAX_RETRIES=99999999999999999 _check_execution_budget >/dev/null 2>&1; echo $?)"
# The bound must not reject values that are merely large but legitimate.
run_test "budget_large_but_valid_is_ok" "BUDGET_INVARIANT=ok" \
  "$(PR_REVIEW_LOOP_EXECUTION_BUDGET=604800 CODERABBIT_RATE_LIMIT_MAX_RETRIES=1000 \
     CODERABBIT_RATE_LIMIT_WAIT=600 _check_execution_budget 2>/dev/null | grep '^BUDGET_INVARIANT=' || true)"

# --area= with no value must not silently degrade to a full run.
run_test "area_filter_empty_equals_value_exits_2" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" \
      bash "$_1562_suite" --area= >/dev/null 2>&1; echo $?)"
run_test "area_filter_empty_value_exits_2" "2" \
  "$(env -u TEST_PR_REVIEW_LOOP_SNAPSHOT PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" \
      bash "$_1562_suite" --area "" >/dev/null 2>&1; echo $?)"

unset _1562_suite _1562_loop _1562_filtered _1562_guard_out

# ---------------------------------------------------------------------------
# Area 19: post-clean settle window and updated_at activity (issue #1556)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 19: post-clean settle and updated_at activity (#1556) ==="

# --- AC-4: the settle window is configurable, per platform ------------------
run_test "settle_config_defined" "yes" \
  "$(type -t _settle_config_for_platform >/dev/null 2>&1 && echo yes || echo no)"
run_test "settle_default_platform" "180 60 30 0" \
  "$(_settle_config_for_platform pr-agent)"
# CodeRabbit gets a longer window because it is the platform that posts late.
run_test "settle_coderabbit_is_longer" "900 120 60 1" \
  "$(_settle_config_for_platform coderabbit)"
run_test "settle_coderabbit_cli_shares_prefix" "900 120 60 1" \
  "$(_settle_config_for_platform coderabbit-cli)"
run_test "settle_generic_env_override" "180 45 30 0" \
  "$(POST_CLEAN_SETTLE_QUIET=45 _settle_config_for_platform pr-agent)"
run_test "settle_per_platform_env_wins" "900 10 10 1" \
  "$(CODERABBIT_POST_CLEAN_SETTLE_QUIET=10 _settle_config_for_platform coderabbit)"
run_test "settle_per_platform_beats_generic" "900 20 20 1" \
  "$(POST_CLEAN_SETTLE_QUIET=99 CODERABBIT_POST_CLEAN_SETTLE_QUIET=20 \
     _settle_config_for_platform coderabbit)"
run_test "settle_window_override" "300 120 60 1" \
  "$(CODERABBIT_POST_CLEAN_SETTLE_WINDOW=300 _settle_config_for_platform coderabbit)"
# Legacy knob still works so existing callers are not silently retimed.
run_test "settle_legacy_post_clean_wait" "180 5 5 0" \
  "$(POST_CLEAN_WAIT=5 _settle_config_for_platform pr-agent)"
run_test "settle_specific_beats_legacy" "180 45 30 0" \
  "$(POST_CLEAN_WAIT=5 POST_CLEAN_SETTLE_QUIET=45 _settle_config_for_platform pr-agent)"
# A quiet period longer than the window could never be satisfied, which would
# burn the whole window and then report settled without ever having been.
run_test "settle_quiet_clamped_to_window" "60 60 30 0" \
  "$(POST_CLEAN_SETTLE_WINDOW=60 POST_CLEAN_SETTLE_QUIET=999 _settle_config_for_platform pr-agent)"
run_test "settle_junk_falls_back_to_default" "180 60 30 0" \
  "$(POST_CLEAN_SETTLE_QUIET=abc _settle_config_for_platform pr-agent)"
run_test "settle_negative_junk_falls_back" "180 60 30 0" \
  "$(POST_CLEAN_SETTLE_QUIET=-5 _settle_config_for_platform pr-agent)"

# --- AC-2 / AC-3: an in-place edit registers as activity --------------------
run_test "activity_probe_defined" "yes" \
  "$(type -t _bot_activity_since >/dev/null 2>&1 && echo yes || echo no)"

_1556_bin="$(mktemp -d)"
_1556_mkgh() {
  # $1 = issue-comments JSON body for the mock to return
  cat > "$_1556_bin/gh" <<GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"issues/42/comments"*) cat <<'JSON'
$1
JSON
    ;;
  *"pulls/42/comments"*) printf '[]\n' ;;
  *"pulls/42/reviews"*)  printf '[]\n' ;;
  *) printf '[]\n' ;;
esac
GHEOF
  chmod +x "$_1556_bin/gh"
}

# The PR #1532 shape exactly: the walkthrough comment was CREATED at 23:23,
# before the 23:34 HEAD commit, and EDITED at 23:52 to carry the new review.
# A created_at-only filter cannot see it; that run only survived because
# CodeRabbit also submitted a formal review, matched separately.
_1556_mkgh '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2026-01-01T23:23:00Z","updated_at":"2026-01-01T23:52:00Z","body":"walkthrough"}]'
run_test "activity_1532_shape_edit_counts" "1" \
  "$(PATH="$_1556_bin:$PATH" _bot_activity_since owner/repo 42 "2026-01-01T23:34:00Z" coderabbitai)"

# The same comment with no edit must NOT count — otherwise every historical
# comment would look like fresh activity and the quiet timer could never expire.
_1556_mkgh '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2026-01-01T23:23:00Z","updated_at":"2026-01-01T23:23:00Z","body":"walkthrough"}]'
run_test "activity_stale_comment_does_not_count" "0" \
  "$(PATH="$_1556_bin:$PATH" _bot_activity_since owner/repo 42 "2026-01-01T23:34:00Z" coderabbitai)"

# A genuinely new comment counts through created_at, as before.
_1556_mkgh '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2026-01-01T23:40:00Z","updated_at":"2026-01-01T23:40:00Z","body":"new"}]'
run_test "activity_new_comment_counts" "1" \
  "$(PATH="$_1556_bin:$PATH" _bot_activity_since owner/repo 42 "2026-01-01T23:34:00Z" coderabbitai)"

# A comment with no updated_at at all must not crash or false-positive.
_1556_mkgh '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2026-01-01T23:23:00Z","body":"no-updated-field"}]'
run_test "activity_missing_updated_at_is_safe" "0" \
  "$(PATH="$_1556_bin:$PATH" _bot_activity_since owner/repo 42 "2026-01-01T23:34:00Z" coderabbitai)"

# Another bot's activity must not satisfy this bot's quiet period.
_1556_mkgh '[{"user":{"login":"some-other-bot[bot]"},"created_at":"2026-01-01T23:40:00Z","updated_at":"2026-01-01T23:40:00Z","body":"unrelated"}]'
run_test "activity_other_bot_ignored" "0" \
  "$(PATH="$_1556_bin:$PATH" _bot_activity_since owner/repo 42 "2026-01-01T23:34:00Z" coderabbitai)"

# A failed query must report -1, never 0 — a broken probe is not silence.
cat > "$_1556_bin/gh" <<'GHFAIL'
#!/usr/bin/env bash
echo "simulated gh failure" >&2
exit 1
GHFAIL
chmod +x "$_1556_bin/gh"
run_test "activity_probe_failure_is_minus_one" "-1" \
  "$(PATH="$_1556_bin:$PATH" _bot_activity_since owner/repo 42 "2026-01-01T23:34:00Z" coderabbitai)"

rm -rf "$_1556_bin"
unset _1556_bin

# --- The completion signal: silence is not the same as finished -------------
#
# Measured on PR #1573, which is what forced this design. HEAD landed at
# 00:17:29; CodeRabbit posted its WALKTHROUGH comment 48s later at 00:18:17,
# and the loop read that as "reviewed, no findings" and returned clean. The
# actual review was submitted at 00:30:32 — twelve minutes after the
# walkthrough — carrying three findings. A quiet period cannot catch that:
# CodeRabbit was silent for the entire window because it was still working.
run_test "settle_coderabbit_requires_submitted_review" "1" \
  "$(_settle_config_for_platform coderabbit | awk '{print $4}')"
run_test "settle_other_platforms_do_not_require_review" "0" \
  "$(_settle_config_for_platform pr-agent | awk '{print $4}')"
run_test "settle_require_review_overridable" "0" \
  "$(CODERABBIT_POST_CLEAN_REQUIRE_REVIEW=0 _settle_config_for_platform coderabbit | awk '{print $4}')"

# A platform name reaches this function from --platform and from the workflow
# config, neither validated upstream, and was interpolated into an eval. I could
# not craft a working exploit — the uppercase transform breaks the obvious
# vectors — but eval on config-derived data is not a construct worth keeping.
run_test "settle_hostile_platform_name_is_safe" "180 60 30 0" \
  "$(_settle_config_for_platform 'a}">/tmp/settle-probe;${b')"
run_test "settle_hostile_platform_no_side_effect" "absent" \
  "$(rm -f /tmp/settle-probe; _settle_config_for_platform 'a}">/tmp/settle-probe;${b' >/dev/null 2>&1; \
     [ -e /tmp/settle-probe ] && echo present || echo absent)"
# An unusable prefix must degrade to the generic knobs, not discard them.
run_test "settle_hostile_name_still_honours_generic" "180 42 30 0" \
  "$(POST_CLEAN_SETTLE_QUIET=42 _settle_config_for_platform 'we!rd')"
run_test "settle_no_eval_in_lookup" "0" \
  "$(grep_count_or_zero 'eval "v=' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"

run_test "review_probe_defined" "yes" \
  "$(type -t _bot_review_submitted_since >/dev/null 2>&1 && echo yes || echo no)"

_1556_rbin="$(mktemp -d)"
_1556_mkreviews() {
  cat > "$_1556_rbin/gh" <<GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"pulls/42/reviews"*) cat <<'JSON'
$1
JSON
    ;;
  *) printf '[]\n' ;;
esac
GHEOF
  chmod +x "$_1556_rbin/gh"
}

# A walkthrough comment is NOT a submitted review — this is the whole point.
_1556_mkreviews '[]'
run_test "review_probe_no_review_is_zero" "0" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" coderabbitai)"

# The PR #1573 review, submitted 13 minutes after HEAD.
_1556_mkreviews '[{"user":{"login":"coderabbitai[bot]"},"submitted_at":"2026-08-22T00:30:32Z","state":"COMMENTED"}]'
run_test "review_probe_detects_submitted_review" "1" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" coderabbitai)"

# A review from a PREVIOUS head must not satisfy this head.
_1556_mkreviews '[{"user":{"login":"coderabbitai[bot]"},"submitted_at":"2026-08-22T00:10:00Z","state":"COMMENTED"}]'
run_test "review_probe_ignores_stale_review" "0" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" coderabbitai)"

# Another bot's review must not satisfy this bot.
_1556_mkreviews '[{"user":{"login":"other-bot[bot]"},"submitted_at":"2026-08-22T00:30:32Z","state":"COMMENTED"}]'
run_test "review_probe_ignores_other_bot" "0" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" coderabbitai)"

cat > "$_1556_rbin/gh" <<'GHFAIL2'
#!/usr/bin/env bash
echo "simulated failure" >&2; exit 1
GHFAIL2
chmod +x "$_1556_rbin/gh"
run_test "review_probe_failure_is_minus_one" "-1" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" coderabbitai)"
rm -rf "$_1556_rbin"
unset _1556_rbin

# --- AC-1: the loop owns the wait, and the contract says so -----------------
_1556_loop="$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
# The activity probe inside run_coderabbit_review must accept updated_at too;
# that was the specific created_at-only filter reported on PR #1532.
run_test "coderabbit_activity_probe_accepts_updated_at" "1" \
  "$(grep_count_or_zero '(.created_at > $since or (.updated_at // .created_at) > $since)' "$_1556_loop")"
# The verdict must no longer be a single fixed sleep.
run_test "post_clean_no_longer_single_wait" "0" \
  "$(grep_count_or_zero '_interruptible_sleep "$post_clean_wait"' "$_1556_loop")"
run_test "post_clean_emits_settled_field" "yes" \
  "$(grep -q 'print_kv POST_CLEAN_SETTLED ' "$_1556_loop" && echo yes || echo no)"
run_test "post_clean_emits_settled_at" "yes" \
  "$(grep -q 'print_kv POST_CLEAN_SETTLED_AT ' "$_1556_loop" && echo yes || echo no)"
# An exhausted window must be distinguishable from a genuinely quiet one.
run_test "post_clean_reports_timeout_distinctly" "yes" \
  "$(grep -q 'print_kv POST_CLEAN_SETTLE_TIMEOUT 1' "$_1556_loop" && echo yes || echo no)"
# A failed activity probe must never be counted as silence.
run_test "post_clean_probe_failure_not_silence" "yes" \
  "$(grep -q 'not counting this interval as quiet' "$_1556_loop" && echo yes || echo no)"
# Silence before the review lands must not accumulate toward the quiet period.
run_test "post_clean_gates_quiet_on_review" "yes" \
  "$(grep -q 'quiet period starts now' "$_1556_loop" && echo yes || echo no)"
run_test "post_clean_reports_missing_review" "yes" \
  "$(grep -q 'print_kv POST_CLEAN_NO_SUBMITTED_REVIEW 1' "$_1556_loop" && echo yes || echo no)"
run_test "post_clean_anchors_since_to_head_commit" "yes" \
  "$(grep -q 'settle_head_iso=' "$_1556_loop" && echo yes || echo no)"
# The documented knobs must actually appear in --help (AC-4).
for _knob in POST_CLEAN_SETTLE_QUIET POST_CLEAN_SETTLE_WINDOW POST_CLEAN_POLL; do
  run_test "help_documents_$_knob" "yes" \
    "$(grep -q "$_knob=<" "$_1556_loop" && echo yes || echo no)"
done
unset _knob _1556_loop

# ---------------------------------------------------------------------------
# Area 20: the late-thread re-check is one contract, owned by the loop (#1574)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 20: late-thread re-check contract (#1574) ==="

_1574_loop="$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
_1574_p91="$REPO_ROOT/docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"
_1574_p92="$REPO_ROOT/docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md"

# The --help text carried 600/180 for CodeRabbit while the code used 900/120.
# Read both and compare, so the numbers cannot drift apart again.
read -r _1574_cw _1574_cq _ _ <<<"$(_settle_config_for_platform coderabbit)"
_1574_help="$(bash "$_1574_loop" --help 2>&1 || true)"
run_test "help_window_default_matches_code" "$_1574_cw" \
  "$(printf '%s\n' "$_1574_help" | grep -oE 'Maximum total time to spend settling \(default: [0-9]+' | grep -oE '[0-9]+$')"
run_test "help_quiet_default_matches_code" "$_1574_cq" \
  "$(printf '%s\n' "$_1574_help" | grep -oE 'Defaults per platform: [0-9]+ for coderabbit' | grep -oE '[0-9]+')"

# A skipped recheck must say why, so the checklist can tell "nothing could
# arrive late" from "settling was suppressed".
run_test "recheck_skip_reason_emitted" "yes" \
  "$(grep -q 'print_kv POST_CLEAN_RECHECK_SKIP_REASON' "$_1574_loop" && echo yes || echo no)"
for _reason in not_clean compare_mode skip_env no_thread_posting_platforms no_pr_number; do
  run_test "recheck_skip_reason_$_reason" "yes" \
    "$(grep -q "POST_CLEAN_RECHECK_SKIP_REASON $_reason" "$_1574_loop" && echo yes || echo no)"
done
run_test "help_documents_skip_reason" "yes" \
  "$(printf '%s\n' "$_1574_help" | grep -q 'POST_CLEAN_RECHECK_SKIP_REASON=' && echo yes || echo no)"

# Protocol 91 must defer to the loop's settle fields rather than carry a wait
# of its own (AC-2), and Protocols 91/92 must describe one contract (AC-3).
run_test "p91_has_no_fixed_recheck_sleep" "0" \
  "$(grep_count_or_zero 'sleep 10' "$_1574_p91")"
# Both clean paths — settled and no-thread-platforms — emit the head binding,
# and the head is read before any reviewer is dispatched, then compared after.
run_test "loop_emits_head_sha_on_both_clean_paths" "2" \
  "$(grep_count_or_zero 'print_kv POST_CLEAN_HEAD_SHA' "$_1574_loop")"
run_test "loop_reads_head_before_dispatch" "yes" \
  "$(awk '/^loop_head_sha=""/{h=NR} /^aggregate_result="skipped"/{a=NR} END{exit !(h>0 && a>0 && h>a)}' "$_1574_loop" && echo yes || echo no)"
run_test "loop_refuses_head_moved_during_run" "yes" \
  "$(grep -q 'aggregate_reason="head_moved_during_run"' "$_1574_loop" && echo yes || echo no)"
run_test "p91_names_head_moved_during_run" "yes" \
  "$(grep -q 'head_moved_during_run' "$_1574_p91" && echo yes || echo no)"
# A head that moved during a clean run is a re-run, not a fixer cycle: the
# ledger does not count it and neither cap fires on it.
_1574_ledger_body="$(jq -nc '{schema:"reviewer_loop_history.v1",pr_number:42,history_status:"available",entries:[
  {iteration:1,head_sha:"a1",run_id:"r1",result:"needs_fixes",reason:"head_moved_during_run"},
  {iteration:2,head_sha:"a2",run_id:"r1",result:"needs_fixes",reason:"unresolved_review_threads"}]}' \
  | { printf '%s\n' "$REVIEWER_LOOP_HISTORY_MARKER" '```json'; cat; printf '```\n'; })"
run_test "ledger_excludes_head_moved_reruns" "1 1 available" \
  "$(reviewer_loop_history_entries_count "$_1574_ledger_body" r1)"
run_test "cap_skipped_for_head_moved" "yes" \
  "$(grep -q 'if \[ "\$aggregate_reason" = "head_moved_during_run" \]; then' "$_1574_loop" && echo yes || echo no)"
# The label is applied only after a final head re-validation (Check 4).
run_test "p91_revalidates_head_before_label" "yes" \
  "$(awk '/^# Check 4:/{p=1} p && /settle_head_ok \|\| exit 12/{found=1} END{exit !found}' "$_1574_p91" && echo yes || echo no)"
unset _1574_ledger_body
for _field in POST_CLEAN_SETTLED POST_CLEAN_SETTLE_TIMEOUT POST_CLEAN_NO_SUBMITTED_REVIEW POST_CLEAN_SETTLED_AT POST_CLEAN_RECHECK_SKIP_REASON POST_CLEAN_HEAD_SHA; do
  run_test "p91_consumes_$_field" "yes" \
    "$(grep -q "$_field" "$_1574_p91" && echo yes || echo no)"
  run_test "p92_names_$_field" "yes" \
    "$(grep -q "$_field" "$_1574_p92" && echo yes || echo no)"
done
# AC-4: an unsettled clean verdict without a submitted review is refused before
# the label, not merely discouraged after it.
run_test "p91_checklist_refuses_no_submitted_review" "yes" \
  "$(grep -q 'POST_CLEAN_NO_SUBMITTED_REVIEW:-0}" = "1"' "$_1574_p91" && echo yes || echo no)"
# Stale telemetry from a previous invocation must never survive into Check 0.6:
# the Step 7 block clears POST_CLEAN_* before the loop runs and exports nothing
# when the loop exits non-zero.
run_test "p91_step7_clears_stale_settle_vars" "yes" \
  "$(grep -q "grep -o '^POST_CLEAN_\[A-Z_\]\*'" "$_1574_p91" && echo yes || echo no)"
run_test "p91_step7_exports_only_on_zero_exit" "yes" \
  "$(grep -q 'Do not enter Step 8a on this run' "$_1574_p91" && echo yes || echo no)"
# Protocol 91 carries no wait at all any more: the only sleep in 8a.1 was the
# fixed one this issue removes, and the timeout path now goes back to Step 7.
run_test "p91_8a1_has_no_sleep" "0" \
  "$(awk '/^### 8a\.1:/,/^## Step 8b/' "$_1574_p91" | grep -cE '^[[:space:]]*sleep ' || true)"


# Execute the gate, not just grep it: extract Check 0.5 + 0.6 from the
# readiness checklist fence and run them with a stubbed gh.
_1574_gate="$(mktemp)"
{
  cat <<'STUB'
set -euo pipefail
PR_NUMBER=42
TARGET_REPO=owner/repo
gh() {
  case "$*" in
    *headRefOid*) printf '%s\n' "${MOCK_HEAD:-}" ;;
    *) printf '%s\n' "${MOCK_SUMMARY:-}" ;;
  esac
}
STUB
  awk '/^# Check 0\.5:/{p=1} /^# Check 1:/{p=0} p' "$_1574_p91"
} > "$_1574_gate"
run_test "gate_extracted_has_check_0_6" "yes" "$(grep -q '^# Check 0.6' "$_1574_gate" && echo yes || echo no)"
# The extracted gate must parse in every shell the fence's contract names;
# the Check 0.5 jq filter had an unterminated quote until this PR.
run_test "gate_parses_in_bash" "yes" "$(bash -n "$_1574_gate" 2>/dev/null && echo yes || echo no)"
run_test "gate_parses_in_zsh" "yes" "$(if command -v zsh >/dev/null 2>&1; then zsh -n "$_1574_gate" 2>/dev/null && echo yes || echo no; else echo yes; fi)"
_1574_clean='### Automated Reviewer Loop Summary

**Result:** clean — no blocking findings'
_1574_skipped='### Automated Reviewer Loop Summary

**Result:** skipped — no review platforms configured'
_1574_head="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
_1574_run_gate() {
  # $@ = VAR=value assignments; prints the exit status
  local status=0
  env -i PATH="$PATH" MOCK_SUMMARY="$_1574_clean" MOCK_HEAD="$_1574_head" "$@" bash "$_1574_gate" >/dev/null 2>&1 || status=$?
  printf '%s' "$status"
}
run_test "gate_skipped_flag_passes" "0" "$(_1574_run_gate REVIEWER_LOOP_SKIPPED_NO_PLATFORMS=true)"
run_test "gate_skipped_summary_passes" "0" "$(_1574_run_gate MOCK_SUMMARY="$_1574_skipped")"
run_test "gate_missing_fields_refused" "12" "$(_1574_run_gate)"
run_test "gate_no_thread_platforms_passes" "0" "$(_1574_run_gate POST_CLEAN_RECHECK=0 POST_CLEAN_RECHECK_SKIP_REASON=no_thread_posting_platforms POST_CLEAN_HEAD_SHA="$_1574_head")"
# The no-thread path is bound to a head too: a push after Step 7 voids it.
run_test "gate_no_thread_platforms_unbound_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=0 POST_CLEAN_RECHECK_SKIP_REASON=no_thread_posting_platforms)"
run_test "gate_no_thread_platforms_other_head_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=0 POST_CLEAN_RECHECK_SKIP_REASON=no_thread_posting_platforms POST_CLEAN_HEAD_SHA=0123456789012345678901234567890123456789)"
run_test "gate_suppressed_recheck_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=0 POST_CLEAN_RECHECK_SKIP_REASON=skip_env)"
run_test "gate_recheck_without_reason_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=0)"
run_test "gate_settled_passes" "0" "$(_1574_run_gate POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=1 POST_CLEAN_SETTLED_AT=2026-08-22T13:49:18Z POST_CLEAN_HEAD_SHA="$_1574_head")"
# A settled verdict is bound to one head: telemetry without a head, or for a
# head the PR has moved past, is refused.
run_test "gate_settled_without_head_binding_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=1)"
run_test "gate_settled_for_other_head_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=1 POST_CLEAN_HEAD_SHA=0123456789012345678901234567890123456789)"
run_test "gate_no_submitted_review_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=0 POST_CLEAN_SETTLE_TIMEOUT=1 POST_CLEAN_NO_SUBMITTED_REVIEW=1)"
run_test "gate_settle_timeout_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=0 POST_CLEAN_SETTLE_TIMEOUT=1)"
run_test "gate_unsettled_without_flags_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=0)"
# Planted violation: invert the settled comparison and the matrix must notice.
_1574_gate_bad="$(mktemp)"
sed 's/POST_CLEAN_SETTLED:-0}" = "1"/POST_CLEAN_SETTLED:-0}" = "0"/' "$_1574_gate" > "$_1574_gate_bad"
_1574_bad_status=0
env -i PATH="$PATH" MOCK_SUMMARY="$_1574_clean" MOCK_HEAD="$_1574_head" POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=1 POST_CLEAN_HEAD_SHA="$_1574_head" bash "$_1574_gate_bad" >/dev/null 2>&1 || _1574_bad_status=$?
run_test "gate_planted_inversion_is_caught" "12" "$_1574_bad_status"
rm -f "$_1574_gate" "$_1574_gate_bad"
unset -f _1574_run_gate
unset _1574_gate _1574_gate_bad _1574_clean _1574_skipped _1574_bad_status _1574_head
unset _1574_loop _1574_p91 _1574_p92 _1574_cw _1574_cq _1574_help _reason _field

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
