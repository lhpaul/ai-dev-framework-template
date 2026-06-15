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

run_linter_output() {
  local diff_file="$1"
  python3 "$LINTER" --diff-file "$diff_file" 2>&1
}

run_git_linter() {
  local repo_dir="$1"
  if (cd "$repo_dir" && python3 "$LINTER" --base-ref main) >/dev/null 2>&1; then
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

cat > "$TMP_DIR/bad-continuation.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,3 @@
+#!/usr/bin/env bash
+RESULT=$(gh api "repos/example/repo/pulls/1" \
+  --jq '.state' 2>/dev/null || true)
DIFF

cat > "$TMP_DIR/allowed.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+git fetch origin develop 2>/dev/null || true # workflow-shell-guard: allow SH001 - best effort cache refresh
DIFF

cat > "$TMP_DIR/bad-sh002.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+local RESULT=$(gh api "repos/example/repo/pulls/1" --jq '.state')
DIFF

cat > "$TMP_DIR/bad-sh003.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(jq -r '.state' <<< "$payload")
DIFF

cat > "$TMP_DIR/bad-sh003-continuation.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,3 @@
+#!/usr/bin/env bash
+RESULT=$(jq -r '.state' \
+  <<< "$payload")
DIFF

cat > "$TMP_DIR/bad-sh004.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+echo "$branch" | grep "fix/"
DIFF

cat > "$TMP_DIR/bad-sh005.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+declare -A seen=([one]=1)
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

cat > "$TMP_DIR/comment-only.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,3 @@
+
+# gh api "repos/example/repo/pulls/1" || true
+echo "safe"
DIFF

cat > "$TMP_DIR/multi-finding.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,3 @@
+#!/usr/bin/env bash
+local RESULT=$(gh api "repos/example/repo/pulls/1" --jq '.state' 2>/dev/null || true)
+declare -A seen=([one]=1)
DIFF

git_repo="$TMP_DIR/git-repo"
mkdir -p "$git_repo/scripts/development-workflow"
(
  cd "$git_repo"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test User"
  printf '%s\n' '#!/usr/bin/env bash' 'echo safe' > scripts/development-workflow/example.sh
  git add scripts/development-workflow/example.sh
  git commit -q -m "test: seed repo"
  git checkout -q -b feature
  printf '%s\n' 'RESULT=$(gh api "repos/example/repo/pulls/1" --jq '"'"'.state'"'"' 2>/dev/null || true)' >> scripts/development-workflow/example.sh
  git add scripts/development-workflow/example.sh
  git commit -q -m "test: add suppressed command"
)

run_test "critical_suppression_fails" "fail" "$(run_linter "$TMP_DIR/bad.diff")"
run_test "continued_critical_suppression_fails" "fail" "$(run_linter "$TMP_DIR/bad-continuation.diff")"
run_test "inline_suppression_passes" "pass" "$(run_linter "$TMP_DIR/allowed.diff")"
run_test "sh002_local_assignment_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh002.diff")"
run_test "sh003_unguarded_jq_assignment_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh003.diff")"
run_test "sh003_continuation_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh003-continuation.diff")"
run_test "sh004_unanchored_grep_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh004.diff")"
run_test "sh005_assoc_array_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh005.diff")"
run_test "noncritical_grep_passes" "pass" "$(run_linter "$TMP_DIR/benign.diff")"
run_test "blank_and_comment_added_lines_pass" "pass" "$(run_linter "$TMP_DIR/comment-only.diff")"
run_test "out_of_scope_path_passes" "pass" "$(run_linter "$TMP_DIR/out-of-scope.diff")"
run_test "context_line_ignored" "pass" "$(run_linter "$TMP_DIR/context-only.diff")"
run_test "git_diff_mode_detects_added_suppression" "fail" "$(run_git_linter "$git_repo")"

multi_output="$(run_linter_output "$TMP_DIR/multi-finding.diff" || true)"
run_test "multi_finding_reports_sh001" "1" "$(printf '%s\n' "$multi_output" | grep -c 'SH001')"
run_test "multi_finding_reports_sh005" "1" "$(printf '%s\n' "$multi_output" | grep -c 'SH005')"

echo ""
echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
