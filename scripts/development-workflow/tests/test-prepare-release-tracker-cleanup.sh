#!/usr/bin/env bash
# test-prepare-release-tracker-cleanup.sh - release cleanup tracker scope tests.
#
# Usage: bash scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
PASS_COUNT=0
FAIL_COUNT=0

_harness_exit() {
  local status=$?
  rm -rf "$TMP_ROOT"
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _harness_exit EXIT

mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  "auth status")
    exit 0
    ;;
  "pr list --state merged --head release/v1.17.0 --base main --json number --jq .[0].number // empty")
    printf '331\n'
    ;;
  "pr list --state merged --head release/v1.17.0 --base develop --json number --jq .[0].number // empty")
    printf '332\n'
    ;;
  "pr list --state open --head release/v1.17.0 --base main --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  "pr list --state open --head release/v1.17.0 --base develop --json number --jq .[0].number // empty")
    printf '\n'
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH

cat > "$MOCK_BIN/git" <<'MOCK_GIT'
#!/usr/bin/env bash
case "$*" in
  "fetch origin --prune")
    exit 0
    ;;
  "ls-remote --exit-code --heads origin release/v1.17.0")
    exit 2
    ;;
  "show-ref --quiet refs/heads/release/v1.17.0")
    exit 1
    ;;
  *)
    printf 'unexpected git invocation: git %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GIT

chmod +x "$MOCK_BIN/gh" "$MOCK_BIN/git"
export PATH="$MOCK_BIN:$PATH"

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_contains() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if grep -Fq -- "$expected" <<< "$actual"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected output to contain '${expected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

fixture_repo() {
  local name="$1"
  local path="$TMP_ROOT/$name"
  mkdir -p "$path/scripts/development-workflow"
  cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" "$path/scripts/development-workflow/workflow-lib.sh"
  cp "$REPO_ROOT/scripts/development-workflow/prepare-release-post-merge-cleanup.sh" "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  chmod +x "$path/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
  cat > "$path/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: linear
YAML
  cat > "$path/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

## [1.17.0] - 2026-06-11

- Released bulk import work LEA-132–LEA-134 and follow-up LEA-140.
- Also shipped dashboard polish LEA-134 and internal note #914.

## [1.16.0] - 2026-06-01

- Older entry LEA-100.
MD
  printf '%s\n' "$path"
}

run_cleanup() {
  local repo="$1"
  shift
  local output=""
  local status=0

  set +e
  output="$(cd "$repo" && ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh "$@" 2>&1)"
  status=$?
  set -e

  printf '%s\n%s\n' "$status" "$output"
}

echo ""
echo "=== Prepare-release tracker cleanup ==="

repo_from_changelog="$(fixture_repo from-changelog)"
result="$(run_cleanup "$repo_from_changelog" v1.17.0 --from-changelog)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_from_changelog_exits_nonzero" "1" "$status"
run_contains "linear_from_changelog_action" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"
run_contains "linear_from_changelog_incomplete" "TRACKER_INCOMPLETE=1 REASON=linear_status_transition_required" "$output"
run_contains "linear_from_changelog_issues" "TRACKER_ISSUES=LEA-132,LEA-133,LEA-134,LEA-140" "$output"

repo_best_effort="$(fixture_repo best-effort)"
result="$(run_cleanup "$repo_best_effort" v1.17.0 --from-changelog --best-effort)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "linear_best_effort_exits_zero" "0" "$status"
run_contains "linear_best_effort_still_reports_action" "TRACKER_ACTION=linear_mcp_or_api_required" "$output"

repo_missing_scope="$(fixture_repo missing-scope)"
result="$(run_cleanup "$repo_missing_scope" v1.17.0)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "missing_scope_exits_nonzero" "1" "$status"
run_contains "missing_scope_signal" "TRACKER_INCOMPLETE=1 REASON=no_issue_scope" "$output"

repo_missing_version="$(fixture_repo missing-version)"
result="$(run_cleanup "$repo_missing_version" v9.9.9 --from-changelog)"
status="$(printf '%s\n' "$result" | sed -n '1p')"
output="$(printf '%s\n' "$result" | sed '1d')"
run_test "missing_changelog_version_exits_nonzero" "1" "$status"
run_contains "missing_changelog_version_signal" "TRACKER_INCOMPLETE=1 REASON=changelog_scope_unavailable" "$output"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
