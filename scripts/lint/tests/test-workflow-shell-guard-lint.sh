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

cat > "$TMP_DIR/bad-sh004-compound.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+foo && grep "fix/"
DIFF

cat > "$TMP_DIR/bad-sh004-attached.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+echo "$branch" | grep --regexp=fix/foo
DIFF

cat > "$TMP_DIR/bad-sh004-perl.diff" <<'DIFF'
diff --git a/scripts/development-workflow/example.sh b/scripts/development-workflow/example.sh
--- a/scripts/development-workflow/example.sh
+++ b/scripts/development-workflow/example.sh
@@ -1,0 +1,2 @@
+#!/usr/bin/env bash
+grep -P fix/foo README.md
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
run_test "sh004_compound_operator_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh004-compound.diff")"
run_test "sh004_attached_regexp_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh004-attached.diff")"
run_test "sh004_perl_regexp_fails" "fail" "$(run_linter "$TMP_DIR/bad-sh004-perl.diff")"
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

# SH006 fixtures use a runtime token so examples cannot trip their own guard.
write_quiet_diff() {
  local name="$1" content="$2" path="${3:-scripts/development-workflow/tests/example.sh}"
  local count
  count=$(awk 'END { print NR }' <<< "$content")
  printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -0,0 +1,%s @@\n' \
    "$path" "$path" "$path" "$path" "$count" > "$TMP_DIR/$name.diff"
  while IFS= read -r fixture_line; do
    printf '+%s\n' "$fixture_line"
  done <<< "$content" >> "$TMP_DIR/$name.diff"
  perl -pi -e 's/__QUIET_GREP__/grep/g' "$TMP_DIR/$name.diff"
}

for quiet_flags in '-q' '-Fq' '-qiE' '-i -q -F' '--quiet' '--silent'; do
  write_quiet_diff quiet "printf '%s\\n' \"\$input\" | __QUIET_GREP__ $quiet_flags token"
  run_test "sh006_flags_${quiet_flags}" fail "$(run_linter "$TMP_DIR/quiet.diff")"
done
for producer in 'echo "$input"' 'cat input.txt' "jq -r '.name' input.json" 'custom_helper'; do
  write_quiet_diff producer "$producer | __QUIET_GREP__ -q token"
  run_test "sh006_producer_${producer}" fail "$(run_linter "$TMP_DIR/producer.diff")"
done
write_quiet_diff filtered 'printf "%s\n" "$input" | jq -r ".name" | __QUIET_GREP__ -Fq token'
run_test sh006_filtered fail "$(run_linter "$TMP_DIR/filtered.diff")"
write_quiet_diff multiple 'printf "%s\n" "$input" | grep token; echo "$input" | __QUIET_GREP__ -q token; printf "%s" "$input" | __QUIET_GREP__ -q absent'
run_test sh006_later_pipeline_not_lost fail "$(run_linter "$TMP_DIR/multiple.diff")"
write_quiet_diff continuation $'printf "%s\\n" "$input" | \\\n  __QUIET_GREP__ -Fq token'
run_test sh006_continuation fail "$(run_linter "$TMP_DIR/continuation.diff")"
write_quiet_diff suppressed $'printf "%s\\n" "$input" | \\\n  __QUIET_GREP__ -q token # workflow-shell-guard: allow SH006 - intentional fixture'
run_test sh006_continued_suppression pass "$(run_linter "$TMP_DIR/suppressed.diff")"
write_quiet_diff prior_suppression $'# workflow-shell-guard: allow SH006 - previous line does not suppress\nprintf "%s\\n" "$input" | __QUIET_GREP__ -q token'
run_test sh006_previous_line_not_suppression fail "$(run_linter "$TMP_DIR/prior_suppression.diff")"
write_quiet_diff comment_backslash $'# comment ending in \\\nprintf "%s\\n" "$input" | __QUIET_GREP__ -q token'
run_test sh006_added_comment_backslash_does_not_hide_pipeline fail "$(run_linter "$TMP_DIR/comment_backslash.diff")"
write_quiet_diff multi_suppression 'gh api example | __QUIET_GREP__ -q token __BEST_EFFORT_SUPPRESSION__ # workflow-shell-guard: allow SH001 - fixture # workflow-shell-guard: allow SH006 - intentional race'
materialize_best_effort_suppression "$TMP_DIR/multi_suppression.diff"
run_test sh006_multiple_local_suppressions pass "$(run_linter "$TMP_DIR/multi_suppression.diff")"

for safe_command in \
  'grep -Fq token <<< "$input"' \
  'grep -q token input.txt' \
  'printf "%s\n" "$input" | grep -F token > /dev/null' \
  'printf "%s\n" "$input" | grep -- -q' \
  'printf "%s\n" "$input" | grep -e -q' \
  'printf "%s\n" "$input" | grep --regexp -q' \
  'printf "%s\n" "$input" | grep --regexp=-q' \
  'printf "%s\n" "$input" | grep -f -q' \
  'printf "%s\n" "$input" | grep -eq' \
  'printf "%s\n" "$input" | grep -m1 token' \
  'false || grep -q token input.txt' \
  '# printf "%s\n" "$input" | __QUIET_GREP__ -q token' \
  '' '  '; do
  write_quiet_diff safe "$safe_command"
  run_test "sh006_safe_${safe_command}" pass "$(run_linter "$TMP_DIR/safe.diff")"
done
write_quiet_diff production 'printf "%s\n" "$input" | __QUIET_GREP__ -q token' scripts/development-workflow/production.sh
run_test sh006_non_test_path pass "$(run_linter "$TMP_DIR/production.diff")"
write_quiet_diff lint_test 'printf "%s\n" "$input" | __QUIET_GREP__ -q token' scripts/lint/tests/example.sh
run_test sh006_lint_test_path fail "$(run_linter "$TMP_DIR/lint_test.diff")"
write_quiet_diff old_scope 'local RESULT=$(gh api example __BEST_EFFORT_SUPPRESSION__); declare -A seen' scripts/lint/tests/example.sh
materialize_best_effort_suppression "$TMP_DIR/old_scope.diff"
run_test sh006_widening_preserves_old_rule_scope pass "$(run_linter "$TMP_DIR/old_scope.diff")"

cat > "$TMP_DIR/partial.diff" <<'DIFF'
diff --git a/scripts/lint/tests/partial.sh b/scripts/lint/tests/partial.sh
--- a/scripts/lint/tests/partial.sh
+++ b/scripts/lint/tests/partial.sh
@@ -1,2 +1,2 @@
 printf '%s\n' "$input" | \
-grep -F token > /dev/null
+__QUIET_GREP__ -Fq token
DIFF
perl -pi -e 's/__QUIET_GREP__/grep/g' "$TMP_DIR/partial.diff"
partial_status=0
partial_output=$(run_linter_output "$TMP_DIR/partial.diff") || partial_status=$?
run_test sh006_partial_edit_exit 1 "$partial_status"
run_test sh006_partial_edit_location yes "$(grep -Fq 'scripts/lint/tests/partial.sh:2: SH006' <<< "$partial_output" && echo yes || echo no)"
run_test sh006_corrective_diagnostic yes "$(grep -Fq 'here-string/file input or consuming grep' <<< "$partial_output" && echo yes || echo no)"
perl -pi -e 's/^\+grep -Fq token/+grep -F token > \/dev\/null/' "$TMP_DIR/partial.diff"
run_test sh006_same_diff_assertion_corrected pass "$(run_linter "$TMP_DIR/partial.diff")"
cat > "$TMP_DIR/context-quiet.diff" <<'DIFF'
diff --git a/scripts/lint/tests/context.sh b/scripts/lint/tests/context.sh
--- a/scripts/lint/tests/context.sh
+++ b/scripts/lint/tests/context.sh
@@ -1,2 +1,3 @@
 printf '%s\n' "$input" | \
 __QUIET_GREP__ -q token
+echo safe
DIFF
perl -pi -e 's/__QUIET_GREP__/grep/g' "$TMP_DIR/context-quiet.diff"
run_test sh006_context_only_unsafe_not_new pass "$(run_linter "$TMP_DIR/context-quiet.diff")"

for preceding_comment in \
  '# comment ends in \' \
  'echo safe # workflow-shell-guard: allow SH006 - previous comment ends in \'; do
  cat > "$TMP_DIR/comment-context.diff" <<'DIFF'
diff --git a/scripts/lint/tests/comment.sh b/scripts/lint/tests/comment.sh
--- a/scripts/lint/tests/comment.sh
+++ b/scripts/lint/tests/comment.sh
@@ -1,2 +1,2 @@
 CONTEXT_COMMENT
-echo safe
+printf '%s\n' "$input" | __QUIET_GREP__ -q token
DIFF
  perl -pi -e 's/__QUIET_GREP__/grep/g' "$TMP_DIR/comment-context.diff"
  CONTEXT_COMMENT="$preceding_comment" perl -pi -e 's/CONTEXT_COMMENT/$ENV{CONTEXT_COMMENT}/g' "$TMP_DIR/comment-context.diff"
  comment_status=0
  comment_output=$(run_linter_output "$TMP_DIR/comment-context.diff") || comment_status=$?
  run_test "sh006_context_comment_backslash_exit_${preceding_comment}" 1 "$comment_status"
  run_test "sh006_context_comment_backslash_location_${preceding_comment}" yes "$(grep -Fq 'scripts/lint/tests/comment.sh:2: SH006' <<< "$comment_output" && echo yes || echo no)"
done

for hash_word in '"# quoted"' '\#escaped' 'literal#suffix'; do
  write_quiet_diff hash_continuation "printf '%s\\n' $hash_word | "$'\\\n  __QUIET_GREP__ -q token'
  run_test "sh006_hash_word_preserves_continuation_${hash_word}" fail "$(run_linter "$TMP_DIR/hash_continuation.diff")"
done

quiet_repo="$TMP_DIR/quiet-git-repo"
mkdir -p "$quiet_repo/scripts/lint/tests"
(
  cd "$quiet_repo"
  git init -q -b main
  git config user.email test@example.com
  git config user.name 'Test User'
  printf '%s\n' 'printf "%s\n" "$input" | \' 'grep -F baseline > /dev/null' > scripts/lint/tests/partial.sh
  git add scripts/lint/tests/partial.sh
  printf '%s\n' '# comment ends in \' 'echo safe' > scripts/lint/tests/comment.sh
  git add scripts/lint/tests/comment.sh
  git commit -q -m 'test: seed continued command'
  git checkout -q -b feature
  printf '%s\n' 'printf "%s\n" "$input" | \' '__QUIET_GREP__ -Fq token' > scripts/lint/tests/partial.sh
  perl -pi -e 's/__QUIET_GREP__/grep/g' scripts/lint/tests/partial.sh
  git add scripts/lint/tests/partial.sh
  git commit -q -m 'test: plant quiet option'
)
quiet_git_status=0
quiet_git_output=$(cd "$quiet_repo" && python3 "$LINTER" --base-ref main 2>&1) || quiet_git_status=$?
run_test sh006_git_partial_edit_exit 1 "$quiet_git_status"
run_test sh006_git_partial_edit_location yes "$(grep -Fq 'scripts/lint/tests/partial.sh:2: SH006' <<< "$quiet_git_output" && echo yes || echo no)"
(
  cd "$quiet_repo"
  printf '%s\n' 'printf "%s\n" "$input" | \' 'grep -F token > /dev/null' > scripts/lint/tests/partial.sh
  git add scripts/lint/tests/partial.sh
  git commit -q -m 'test: correct the same assertion'
)
run_test sh006_git_same_assertion_corrected pass "$(run_git_linter "$quiet_repo")"

(
  cd "$quiet_repo"
  printf '%s\n' '# comment ends in \' 'printf "%s\n" "$input" | __QUIET_GREP__ -q token' > scripts/lint/tests/comment.sh
  perl -pi -e 's/__QUIET_GREP__/grep/g' scripts/lint/tests/comment.sh
  git add scripts/lint/tests/comment.sh
  git commit -q -m 'test: plant quiet grep after unchanged comment'
)
comment_git_status=0
comment_git_output=$(cd "$quiet_repo" && python3 "$LINTER" --base-ref main 2>&1) || comment_git_status=$?
run_test sh006_git_context_comment_backslash_exit 1 "$comment_git_status"
run_test sh006_git_context_comment_backslash_location yes "$(grep -Fq 'scripts/lint/tests/comment.sh:2: SH006' <<< "$comment_git_output" && echo yes || echo no)"

echo ""
echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
