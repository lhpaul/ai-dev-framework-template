#!/usr/bin/env bash
# pr-review-loop-harness.sh — shared preamble for the pr-review-loop.sh suites.
#
# Sourced (never executed) by every scripts/development-workflow/tests/
# test-pr-review-loop*.sh suite, as their first action after `set -euo
# pipefail`:
#
#     source "<tests dir>/lib/pr-review-loop-harness.sh" "$@"
#
# The harness used to be one 24k-line file. ShellCheck needed ~17 GB of memory
# to lint it, which killed the smaller runners private repositories get and
# made it the slowest suite in CI (#1876). It is now split into several suites
# of a few thousand lines each; everything they share lives here:
#
#   * the immutable-snapshot re-exec and the --area / --list-areas filter
#     (#1562), which act on the calling suite ($0)
#   * repository-root resolution, the mock gh and git on PATH, and the
#     HARNESS_MODE source of pr-review-loop.sh
#   * run_test, run_contains, and grep_count_or_zero
#
# The suites must stay small: test-pr-review-loop.sh's Area 18 asserts a line
# cap on every suite. Add new areas to the suite whose topic fits, or start a
# new test-pr-review-loop-<topic>.sh that sources this file — never grow one
# suite back into a single large file.
#
# bash reads `source`d files whole before running them, so an edit to this file
# while a run is in flight cannot reach that run, the same guarantee the
# snapshot gives the suite itself.

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "ERROR: pr-review-loop-harness.sh must be sourced by a test-pr-review-loop*.sh suite, not run directly" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Run from an immutable snapshot (issue #1562)
# ---------------------------------------------------------------------------
#
# Bash reads a script incrementally rather than loading it whole, so editing
# a suite while a run is in flight makes the running shell pick up part of
# the new text at whatever offset it has reached. During the #1531 work that
# produced a run reporting a pass/fail count matching neither the old file nor
# the new one, with nothing to indicate anything had happened. With minutes
# per run the temptation to edit while waiting is constant, which makes this a
# question of when rather than whether.
#
# So the calling suite ($0) is copied to a temp file and re-executed from
# there. The copy is a single atomic-enough read at startup; once running,
# edits to the working-tree file cannot reach it.
#
# The obvious manual workaround — copy it somewhere immutable and run that —
# does not work on its own, because the repo root (and this library) are
# resolved from the suite's own location. TEST_PR_REVIEW_LOOP_ORIGIN carries
# the original path across the re-exec so both still anchor to the checkout.
#
# --area composes with the snapshot rather than needing its own machinery: the
# areas are contiguous line ranges in a linear script, so a filtered run is
# just a snapshot built from the suite's preamble, the selected ranges, and the
# summary footer. Nothing in a suite's body has to be restructured or wrapped
# in conditionals.
#
# Why it is worth having: Area 13 (the four test-pr-review-loop-failure-paths
# suites) makes ~156 codex-github-reviewer.sh invocations that each really
# sleep, so those suites take minutes while most other areas take seconds.
# --area lets you iterate on one area without waiting for the rest of its suite.
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
Usage: bash test-pr-review-loop[-<topic>].sh [--area <name>]... [--list-areas]

  --area <name>   Run only matching areas of this suite. Matches the area's
                  number or any substring of its title, case-insensitively;
                  repeatable, and a comma-separated list is accepted. Examples:
                    --area 1
                    --area haystack
                    --area 0a --area 1
  --list-areas    Print this suite's area names with their line ranges and exit.

With no arguments the whole suite runs. The pr-review-loop.sh harness is split
across several test-pr-review-loop*.sh suites; each filters only its own areas.
USAGE
        exit 0
        ;;
      *) echo "ERROR: unknown argument '$1'" >&2; exit 2 ;;
    esac
  done

  # Honour a pre-set origin so a copy of a suite placed outside the checkout
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
  # gh pr view --json headRefName,headRepositoryOwner,headRepository,isCrossRepository
  # — pr-ownership-guard.sh's own read (issue #1837's apply-readiness-labels.sh
  # ownership guard calls this before any other PR-state read). Tests set
  # MOCK_GH_OWNERSHIP_BRANCH to the same branch they pass as this function's
  # own --branch/second positional argument so the guard resolves `owned`; an
  # unset value returns an empty headRefName, which mismatches any real
  # --expected-branch and is the fail-closed default for tests that do not
  # care about reaching the mutation.
  *"headRefName,headRepositoryOwner,headRepository,isCrossRepository"*)
    printf '{"headRefName":"%s","headRepositoryOwner":{"login":"acme"},"headRepository":{"name":"widgets"},"isCrossRepository":false}\n' \
      "${MOCK_GH_OWNERSHIP_BRANCH:-}"
    exit "${MOCK_GH_EXIT:-0}"
    ;;
  # gh repo view --json nameWithOwner --jq '.nameWithOwner' — apply-readiness-
  # labels.sh's repo_slug() fallback (no --repo given), consulted by the
  # ownership guard as its target repository. This mock does not apply --jq
  # itself, so it must print the already-filtered bare slug a real `gh ...
  # --jq` would, matching the ownership payload's acme/widgets above so the
  # two agree by default with no per-test wiring.
  *"repo view"*"nameWithOwner"*)
    printf '%s\n' "${MOCK_GH_REPO_SLUG:-acme/widgets}"
    exit "${MOCK_GH_EXIT:-0}"
    ;;
  # gh pr view --json headRefOid — used by run_copilot_review to resolve head SHA.
  # Tests set MOCK_GH_HEAD_SHA to control the returned value; default empty string
  # triggers the head-sha-unavailable escalation path.
  # When statusCheckRollup is also requested (#1649 expensive gate baseline helper),
  # return the combined payload from MOCK_GH_PR_VIEW_ROLLUP (full JSON object).
  # Do not use ${VAR:-{...}} here: bash ends the expansion at the first `}` inside
  # the default, so a set MOCK_GH_PR_VIEW_ROLLUP would be printed with a trailing
  # literal `}` and become invalid JSON.
  *"statusCheckRollup"*)
    if [ -n "${MOCK_GH_PR_VIEW_ROLLUP+x}" ]; then
      printf '%s\n' "$MOCK_GH_PR_VIEW_ROLLUP"
    else
      printf '{"statusCheckRollup":[],"headRefOid":"%s"}\n' "${MOCK_GH_HEAD_SHA:-}"
    fi
    exit "${MOCK_GH_EXIT:-0}"
    ;;
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
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
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
# shellcheck disable=SC2034  # read by the suites that source this file
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

run_contains() {
  local name="$1"
  local needle="$2"
  local haystack="$3"
  if grep -Fq -- "$needle" <<< "$haystack"; then
    echo "PASS: $name"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
  else
    echo "FAIL: $name — expected substring '${needle}'"
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
