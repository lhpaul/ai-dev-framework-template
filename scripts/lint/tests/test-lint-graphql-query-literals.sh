#!/usr/bin/env bash
# test-lint-graphql-query-literals.sh - Unit tests for lint-graphql-query-literals.py.
#
# #1828: a `gh api graphql` query literal in apply-readiness-labels.sh shipped
# with one extra closing brace. The test suite mocks `gh`, so the malformed
# literal stayed green until it hit GitHub live. #1836 generalizes the
# tokenizer proven in test-apply-readiness-labels.sh into a repo-wide lint
# (scripts/lint/lint-graphql-query-literals.py) so the next unbalanced query
# anywhere under scripts/ is caught before merge, regardless of which file it
# lands in.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir)"
case "$GIT_COMMON_DIR" in
  /*) REPO_ROOT="$(cd "$GIT_COMMON_DIR/.." && pwd -P)" ;;
  *)  REPO_ROOT="$(cd "$SCRIPT_DIR/$GIT_COMMON_DIR/.." && pwd -P)" ;;
esac

LINTER="$REPO_ROOT/scripts/lint/lint-graphql-query-literals.py"
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

# run_linter <fixture-path> -> "pass" | "fail" (exit code 0 vs non-zero)
run_linter() {
  local target="$1"
  if python3 "$LINTER" "$target" >/dev/null 2>&1; then
    printf 'pass'
  else
    printf 'fail'
  fi
}

write_fixture() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$@" > "$path"
}

# --- Balanced fixtures pass ---------------------------------------------------

write_fixture "$TMP_DIR/balanced.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query{repository{pullRequest{id}}}'"
run_test "balanced_literal_passes" "pass" "$(run_linter "$TMP_DIR/balanced.sh")"

# --- Planted-violation proof: the exact #1828 defect shape -------------------

write_fixture "$TMP_DIR/extra_brace.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query{repository{pullRequest{id}}}}'"
run_test "extra_closing_brace_fails" "fail" "$(run_linter "$TMP_DIR/extra_brace.sh")"

# Equal totals, wrong order: a counting-only checker would miss this.
write_fixture "$TMP_DIR/misnested.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query{repository}}{'"
run_test "misnested_delimiters_fail" "fail" "$(run_linter "$TMP_DIR/misnested.sh")"

write_fixture "$TMP_DIR/crossed.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query(\$a:Int{x)}'"
run_test "crossed_delimiters_fail" "fail" "$(run_linter "$TMP_DIR/crossed.sh")"

write_fixture "$TMP_DIR/bracket.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query(\$a:[Int!){x}'"
run_test "unbalanced_bracket_fails" "fail" "$(run_linter "$TMP_DIR/bracket.sh")"

# --- Delimiters inside GraphQL strings/comments are data, not syntax ---------

write_fixture "$TMP_DIR/string_value.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query{a(s:\")}\\\"(\"){id} b(t:\"\"\"{)\"\"\"){id}}'"
run_test "delimiters_in_strings_ignored" "pass" "$(run_linter "$TMP_DIR/string_value.sh")"

write_fixture "$TMP_DIR/string_hides_brace.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query{a(s:\"}\"){id}'"
run_test "brace_beside_string_still_caught" "fail" "$(run_linter "$TMP_DIR/string_hides_brace.sh")"

write_fixture "$TMP_DIR/comment.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query # })" '{' ' field' "}'"
run_test "delimiters_in_comments_ignored" "pass" "$(run_linter "$TMP_DIR/comment.sh")"

write_fixture "$TMP_DIR/unterminated_string.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query{a(s:\"})'"
run_test "unterminated_graphql_string_fails" "fail" "$(run_linter "$TMP_DIR/unterminated_string.sh")"

# --- Bash-level string concatenation (pr-review-loop.sh's real shape) -------
# graphql_query='...'"$var"'...' is one logical literal built by adjacent bash
# quoting. Without concatenation awareness the scanner would stop at the
# first embedded quote and flag the truncated head as unbalanced.

write_fixture "$TMP_DIR/concat_balanced.sh" \
  '#!/usr/bin/env bash' \
  "local pr_fields='commits(last:1){nodes{commit{committedDate}}}'" \
  "graphql_query='query{repository{pullRequest{'\"\$pr_fields\"'reviewThreads{id}}}}'"
run_test "concatenated_balanced_literal_passes" "pass" "$(run_linter "$TMP_DIR/concat_balanced.sh")"

write_fixture "$TMP_DIR/concat_unbalanced.sh" \
  '#!/usr/bin/env bash' \
  "graphql_query='query{repository{pullRequest{'\"\$pr_fields\"'reviewThreads{id}}}}}'"
run_test "concatenated_unbalanced_literal_fails" "fail" "$(run_linter "$TMP_DIR/concat_unbalanced.sh")"

# --- Repo-wide recursion: multiple files, one findings report ---------------

rm -rf "$TMP_DIR/tree"
write_fixture "$TMP_DIR/tree/a/one.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query{a}'"
write_fixture "$TMP_DIR/tree/b/two.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query{b}}'"
run_test "recursive_scan_finds_nested_violation" "fail" "$(run_linter "$TMP_DIR/tree")"
rm -f "$TMP_DIR/tree/b/two.sh"
run_test "recursive_scan_clean_after_fix" "pass" "$(run_linter "$TMP_DIR/tree")"

# --- tests/ fixtures are excluded from the scan -----------------------------
# This checker's own test fixtures (and test-protocol-91-readiness-checklist.sh's
# embedded Python regex source) deliberately contain malformed or regex-shaped
# `query='...'` text that is not a real `gh api graphql` call.

rm -rf "$TMP_DIR/excl"
write_fixture "$TMP_DIR/excl/tests/fixture.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query{unbalanced}}'"
run_test "tests_directory_excluded_from_scan" "pass" "$(run_linter "$TMP_DIR/excl")"

# --- Self-check: the real repo tree is currently clean ----------------------

run_test "repo_scripts_tree_is_currently_clean" "pass" "$(run_linter "$REPO_ROOT/scripts")"

echo ""
echo "$PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
