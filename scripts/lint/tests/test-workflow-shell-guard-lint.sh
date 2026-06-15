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

BEST_EFFORT_SUPPRESSION="$(printf '%s%s %s' '|' '|' 'true')"

materialize_best_effort_suppression() {
  local diff_file="$1"
  perl -0pi -e 's/__BEST_EFFORT_SUPPRESSION__/'"$BEST_EFFORT_SUPPRESSION"'/g' "$diff_file"
}

cat > "$TMP_DIR/bad.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(gh api "repos/example/repo/pulls/1" --jq '.state' 2>/dev/null __BEST_EFFORT_SUPPRESSION__)
DIFF

cat > "$TMP_DIR/bad-continuation.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,3 @@
+#!/usr/bin/env bash
+RESULT=$(gh api "repos/example/repo/pulls/1" \
+  --jq '.state' 2>/dev/null __BEST_EFFORT_SUPPRESSION__)
DIFF

cat > "$TMP_DIR/allowed.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+git fetch origin develop 2>/dev/null __BEST_EFFORT_SUPPRESSION__ # workflow-shell-guard: allow SH001 - best effort cache refresh
DIFF

cat > "$TMP_DIR/bad-sh002.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+local RESULT=$(gh api "repos/example/repo/pulls/1" --jq '.state')
DIFF

cat > "$TMP_DIR/allowed-sh002.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+local RESULT=$(gh api "repos/example/repo/pulls/1" --jq '.state') # workflow-shell-guard: allow SH002 - compound assignment is intentional here
DIFF

cat > "$TMP_DIR/bad-sh003.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(jq -r '.state' <<< "$payload")
DIFF

cat > "$TMP_DIR/bad-sh003-local.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+local RESULT=$(jq -r '.state' <<< "$payload")
DIFF

cat > "$TMP_DIR/bad-sh003-filter.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(jq -r '.state || .fallback' <<< "$payload")
DIFF

cat > "$TMP_DIR/bad-sh003-filter-like-flag.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(jq -r '-e' <<< "$payload")
DIFF

cat > "$TMP_DIR/allowed-sh003.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(jq -r '.state || .fallback' <<< "$payload") # workflow-shell-guard: allow SH003 - jq filter uses fallback logic intentionally
DIFF

cat > "$TMP_DIR/allowed-sh003-e.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(jq -e -r '.state' <<< "$payload")
DIFF

cat > "$TMP_DIR/allowed-sh003-exit-status.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(jq --exit-status -r '.state' <<< "$payload")
DIFF

cat > "$TMP_DIR/allowed-sh003-er.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(jq -er '.state' <<< "$payload")
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

cat > "$TMP_DIR/bad-sh004-attached.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+echo "$branch" | grep --regexp=fix/foo
DIFF

cat > "$TMP_DIR/bad-sh004-file-before-e.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+grep README.md -e fix/foo
DIFF

cat > "$TMP_DIR/malformed-snippet.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(jq -r '.state <<< "$payload")
DIFF

cat > "$TMP_DIR/allowed-sh004.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+echo "$branch" | grep "^feature/"
DIFF

cat > "$TMP_DIR/allowed-sh004-attached.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+echo "$branch" | grep --regexp='^feature/'
DIFF

cat > "$TMP_DIR/bad-sh005.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+declare -A seen=([one]=1)
DIFF

cat > "$TMP_DIR/allowed-sh005.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+declare -A seen=([one]=1) # workflow-shell-guard: allow SH005 - associative array is intentional here
DIFF

cat > "$TMP_DIR/bad-invalid-suppression.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+git fetch origin develop 2>/dev/null __BEST_EFFORT_SUPPRESSION__ # workflow-shell-guard: allow BADTAG - malformed tag must not suppress
DIFF

cat > "$TMP_DIR/benign.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+matches="$(printf '%s\n' "$text" | grep -c foo __BEST_EFFORT_SUPPRESSION__)"
DIFF

cat > "$TMP_DIR/out-of-scope.diff" <<'DIFF'
diff --git a/docs/example.sh b/docs/example.sh
--- a/docs/example.sh
+++ b/docs/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+RESULT=$(gh api "repos/example/repo/pulls/1" --jq '.state' 2>/dev/null __BEST_EFFORT_SUPPRESSION__)
DIFF

cat > "$TMP_DIR/context-only.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,2 +1,3 @@
 RESULT=$(gh api "repos/example/repo/pulls/1" --jq '.state' 2>/dev/null __BEST_EFFORT_SUPPRESSION__)
+echo "new safe line"
DIFF

cat > "$TMP_DIR/comment-only.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,3 @@
+
+# gh api "repos/example/repo/pulls/1" __BEST_EFFORT_SUPPRESSION__
+echo "safe"
DIFF

cat > "$TMP_DIR/multi-finding.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,3 @@
+#!/usr/bin/env bash
+local RESULT=$(gh api "repos/example/repo/pulls/1" --jq '.state' 2>/dev/null __BEST_EFFORT_SUPPRESSION__)
+declare -A seen=([one]=1)
DIFF

cat > "$TMP_DIR/multi-dedup.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+local RESULT=$(jq -r '.state' <<< "$payload")
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
  printf '%s\n' 'RESULT=$(gh api "repos/example/repo/pulls/1" --jq '"'"'.state'"'"' 2>/dev/null __BEST_EFFORT_SUPPRESSION__)' >> scripts/development-workflow/example.sh
  materialize_best_effort_suppression scripts/development-workflow/example.sh
  git add scripts/development-workflow/example.sh
  git commit -q -m "test: add suppressed command"
)

for _fixture in \
  "$TMP_DIR/bad.diff" \
  "$TMP_DIR/bad-continuation.diff" \
  "$TMP_DIR/allowed.diff" \
  "$TMP_DIR/allowed-sh002.diff" \
  "$TMP_DIR/benign.diff" \
  "$TMP_DIR/out-of-scope.diff" \
  "$TMP_DIR/context-only.diff" \
  "$TMP_DIR/comment-only.diff" \
  "$TMP_DIR/multi-finding.diff" \
  "$TMP_DIR/bad-sh004-attached.diff" \
  "$TMP_DIR/allowed-sh004-attached.diff" \
  "$TMP_DIR/allowed-sh005.diff" \
  "$TMP_DIR/bad-invalid-suppression.diff"; do
  [ -e "$_fixture" ] && materialize_best_effort_suppression "$_fixture"
done
unset _fixture

run_test "critical_suppression_fails" "fail" "$(run_linter "$TMP_DIR/bad.diff")"
run_test "continued_critical_suppression_fails" "fail" "$(run_linter "$TMP_DIR/bad-continuation.diff")"
run_test "inline_suppression_passes" "pass" "$(run_linter "$TMP_DIR/allowed.diff")"
run_test "sh002_local_assignment_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh002.diff")"
run_test "sh002_allowed_directive_passes" "pass" "$(run_linter "$TMP_DIR/allowed-sh002.diff")"
run_test "sh003_unguarded_jq_assignment_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh003.diff")"
run_test "sh003_local_assignment_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh003-local.diff")"
run_test "sh003_filter_lookalike_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh003-filter.diff")"
run_test "sh003_filter_like_flag_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh003-filter-like-flag.diff")"
run_test "sh003_allowed_directive_passes" "pass" "$(run_linter "$TMP_DIR/allowed-sh003.diff")"
run_test "sh003_jq_e_passes" "pass" "$(run_linter "$TMP_DIR/allowed-sh003-e.diff")"
run_test "sh003_jq_exit_status_passes" "pass" "$(run_linter "$TMP_DIR/allowed-sh003-exit-status.diff")"
run_test "sh003_jq_er_passes" "pass" "$(run_linter "$TMP_DIR/allowed-sh003-er.diff")"
run_test "sh003_continuation_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh003-continuation.diff")"
run_test "sh004_unanchored_grep_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh004.diff")"
run_test "sh004_attached_regexp_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh004-attached.diff")"
run_test "sh004_file_before_e_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh004-file-before-e.diff")"
run_test "sh004_anchored_grep_passes" "pass" "$(run_linter "$TMP_DIR/allowed-sh004.diff")"
run_test "sh004_attached_regexp_passes" "pass" "$(run_linter "$TMP_DIR/allowed-sh004-attached.diff")"
run_test "sh005_assoc_array_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh005.diff")"
run_test "sh005_allowed_directive_passes" "pass" "$(run_linter "$TMP_DIR/allowed-sh005.diff")"
run_test "invalid_suppression_tag_does_not_pass" "fail" "$(run_linter "$TMP_DIR/bad-invalid-suppression.diff")"
run_test "malformed_snippet_does_not_crash" "pass" "$(run_linter "$TMP_DIR/malformed-snippet.diff")"
run_test "noncritical_grep_passes" "pass" "$(run_linter "$TMP_DIR/benign.diff")"
run_test "blank_and_comment_added_lines_pass" "pass" "$(run_linter "$TMP_DIR/comment-only.diff")"
run_test "out_of_scope_path_passes" "pass" "$(run_linter "$TMP_DIR/out-of-scope.diff")"
run_test "context_line_ignored" "pass" "$(run_linter "$TMP_DIR/context-only.diff")"
run_test "git_diff_mode_detects_added_suppression" "fail" "$(run_git_linter "$git_repo")"

multi_output="$(run_linter_output "$TMP_DIR/multi-finding.diff" || true)"
run_test "multi_finding_reports_sh001" "1" "$(printf '%s\n' "$multi_output" | grep -c 'SH001')"
run_test "multi_finding_reports_sh005" "1" "$(printf '%s\n' "$multi_output" | grep -c 'SH005')"

dedup_output="$(run_linter_output "$TMP_DIR/multi-dedup.diff" || true)"
run_test "dedup_reports_only_sh002" "1" "$(printf '%s\n' "$dedup_output" | grep -c 'SH002')"
run_test "dedup_reports_no_sh003" "0" "$(printf '%s\n' "$dedup_output" | grep -c 'SH003')"

echo ""
echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
