#!/usr/bin/env bash
# test-workflow-shell-guard-lint.sh - Unit tests for workflow-shell-guard-lint.py.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir)"
case "$GIT_COMMON_DIR" in
  /*) REPO_ROOT="$(cd "$GIT_COMMON_DIR/.." && pwd -P)" ;;
  *)  REPO_ROOT="$(cd "$SCRIPT_DIR/$GIT_COMMON_DIR/.." && pwd -P)" ;;
esac

LINTER="$REPO_ROOT/scripts/lint/workflow-shell-guard-lint.py"
TMP_DIR="$(mktemp -d)"

_harness_exit() {
  local status=$?
  rm -rf "$TMP_DIR"
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _harness_exit EXIT

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
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  fi
}

run_linter() {
  local diff_file="$1"
  if python3 "$LINTER" --diff-file "$diff_file" >/dev/null 2>&1; then
    printf 'pass'
  else
    printf 'fail'
  fi
}

cat > "$TMP_DIR/bad.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(gh api "repos/example/repo/pulls/1" --jq '.state' 2>/dev/null || true)
DIFF

cat > "$TMP_DIR/allowed.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+git fetch origin develop 2>/dev/null || true # workflow-shell-guard: allow SH001 - best effort cache refresh
DIFF

cat > "$TMP_DIR/benign.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+matches="$(printf '%s\n' "$text" | grep -c foo || true)"
DIFF

cat > "$TMP_DIR/out-of-scope.diff" <<'DIFF'
diff --git a/docs/example.sh b/docs/example.sh
--- a/docs/example.sh
+++ b/docs/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(gh api "repos/example/repo/pulls/1" --jq '.state' 2>/dev/null || true)
DIFF

cat > "$TMP_DIR/context-only.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,2 +1,3 @@
 RESULT=$(gh api "repos/example/repo/pulls/1" --jq '.state' 2>/dev/null || true)
+echo "new safe line"
DIFF

run_test "critical_suppression_fails" "fail" "$(run_linter "$TMP_DIR/bad.diff")"
run_test "inline_suppression_passes" "pass" "$(run_linter "$TMP_DIR/allowed.diff")"
run_test "noncritical_grep_passes" "pass" "$(run_linter "$TMP_DIR/benign.diff")"
run_test "out_of_scope_path_passes" "pass" "$(run_linter "$TMP_DIR/out-of-scope.diff")"
run_test "context_line_ignored" "pass" "$(run_linter "$TMP_DIR/context-only.diff")"

echo ""
echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
