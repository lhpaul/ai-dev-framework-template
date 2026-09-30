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
# Resolve the toplevel of the *current checkout* (worktree or main clone),
# not the shared main-clone root via --git-common-dir. lint-graphql-query-literals.py
# and this test are added together in the same branch, so in a linked
# worktree (this framework's normal dev environment) a --git-common-dir-based
# resolution would point at the main clone's checkout of `develop`, where
# neither file exists yet, and every test below would fail for the wrong
# reason (linter not found) rather than testing the linter itself.
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

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
write_fixture "$TMP_DIR/excl/prod.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query{ok}'"
run_test "tests_directory_excluded_from_scan" "pass" "$(run_linter "$TMP_DIR/excl")"

# The exclusion is relative to the scan root: a root that itself lives under
# a directory named `tests` must still be scanned.
rm -rf "$TMP_DIR/tests/root"
write_fixture "$TMP_DIR/tests/root/prod.sh" \
  '#!/usr/bin/env bash' \
  "gh api graphql -f query='query{bad}}'"
run_test "root_under_tests_dir_still_scanned" "fail" "$(run_linter "$TMP_DIR/tests/root")"

# A run that examines no shell file refuses to read as a pass (exit 2).
rm -rf "$TMP_DIR/empty"
mkdir -p "$TMP_DIR/empty"
set +e
python3 "$LINTER" "$TMP_DIR/empty" >/dev/null 2>&1
empty_rc=$?
set -e
run_test "empty_scan_exits_2" "2" "$empty_rc"

# --- Shell comments are not query literals ----------------------------------

write_fixture "$TMP_DIR/shell_comment.sh" \
  '#!/usr/bin/env bash' \
  "# example: gh api graphql -f query='query{" \
  "gh api graphql -f query='query{ok}'"
run_test "query_in_shell_comment_ignored" "pass" "$(run_linter "$TMP_DIR/shell_comment.sh")"

# --- Only GraphQL query literals are recognised (false-positive guards) -----
# Each fixture also carries one balanced real query so the file is examined.

write_fixture "$TMP_DIR/fp_prose.sh" \
  '#!/usr/bin/env bash' \
  "echo \"hint: set query='(unbalanced prose\" >&2" \
  "gh api graphql -f query='query{ok}'"
run_test "non_graphql_query_text_ignored" "pass" "$(run_linter "$TMP_DIR/fp_prose.sh")"

write_fixture "$TMP_DIR/fp_midword.sh" \
  '#!/usr/bin/env bash' \
  "obj.query='query{a}}'" \
  "gh api graphql -f query='query{ok}'"
run_test "mid_word_query_text_ignored" "pass" "$(run_linter "$TMP_DIR/fp_midword.sh")"

write_fixture "$TMP_DIR/fp_nographql.sh" \
  '#!/usr/bin/env bash' \
  "sql_query='query ( select'"
set +e
python3 "$LINTER" "$TMP_DIR/fp_nographql.sh" >/dev/null 2>&1
nographql_rc=$?
set -e
run_test "file_without_graphql_has_no_findings" "0" "$nographql_rc"

# Non-executed shell text: double-quoted strings, trailing comments, and
# heredoc bodies are data, not a literal passed to `gh api graphql`.
write_fixture "$TMP_DIR/fp_dq_echo.sh" \
  '#!/usr/bin/env bash' \
  "echo \"gh api graphql -f query='query{bad}}'\"" \
  "gh api graphql -f query='query{ok}'"
run_test "query_inside_double_quotes_ignored" "pass" "$(run_linter "$TMP_DIR/fp_dq_echo.sh")"

write_fixture "$TMP_DIR/fp_inline_comment.sh" \
  '#!/usr/bin/env bash' \
  "true # gh api graphql -f query='query{bad}}'" \
  "gh api graphql -f query='query{ok}'"
run_test "query_in_trailing_comment_ignored" "pass" "$(run_linter "$TMP_DIR/fp_inline_comment.sh")"

write_fixture "$TMP_DIR/fp_heredoc.sh" \
  '#!/usr/bin/env bash' \
  "cat <<'DOC'" \
  "gh api graphql -f query='query{bad}}'" \
  'DOC' \
  "gh api graphql -f query='query{ok}'"
run_test "query_in_heredoc_body_ignored" "pass" "$(run_linter "$TMP_DIR/fp_heredoc.sh")"

# Any valid Bash heredoc delimiter, not only identifier-style ones.
write_fixture "$TMP_DIR/fp_heredoc_delims.sh" \
  '#!/usr/bin/env bash' \
  "cat <<'END-DOC'" \
  "gh api graphql -f query='query{bad}}'" \
  'END-DOC' \
  'cat <<"a.b"' \
  "gh api graphql -f query='query{bad}}'" \
  'a.b' \
  'cat <<\EOF' \
  "gh api graphql -f query='query{bad}}'" \
  'EOF' \
  "gh api graphql -f query='query{ok}'"
run_test "heredoc_nonidentifier_delimiters_ignored" "pass" "$(run_linter "$TMP_DIR/fp_heredoc_delims.sh")"

# Arithmetic left shift is not a heredoc operator: it must not swallow the
# rest of the file.
write_fixture "$TMP_DIR/arith_shift.sh" \
  '#!/usr/bin/env bash' \
  'x=$(( y << z ))' \
  'echo "$(( a << b ))"' \
  '(( m <<= 1 ))' \
  "gh api graphql -f query='query{a{b}}}'"
run_test "arithmetic_shift_does_not_swallow_following_query" "fail" "$(run_linter "$TMP_DIR/arith_shift.sh")"

# ...but a command substitution inside double quotes is code again: the
# common real shape `var="$(gh api graphql -f query='...')"` is still caught.
write_fixture "$TMP_DIR/cmdsubst_in_dq.sh" \
  '#!/usr/bin/env bash' \
  "result=\"\$(gh api graphql -f query='query{a{b}}}' --jq .data)\""
run_test "command_substitution_in_double_quotes_caught" "fail" "$(run_linter "$TMP_DIR/cmdsubst_in_dq.sh")"

# Lexer false-negative guards: constructs that must not make the lexer
# swallow or misclassify a following real query.
write_fixture "$TMP_DIR/herestring.sh" \
  '#!/usr/bin/env bash' \
  'cat <<< "x"' \
  'grep y <<<foo' \
  "gh api graphql -f query='query{a{b}}}'"
run_test "here_string_does_not_swallow_following_query" "fail" "$(run_linter "$TMP_DIR/herestring.sh")"

write_fixture "$TMP_DIR/case_in_cmdsubst.sh" \
  '#!/usr/bin/env bash' \
  "x=\"\$(case \$a in a) echo 1;; (b) echo 2;; esac; gh api graphql -f query='query{a{b}}}')\""
run_test "case_pattern_paren_does_not_close_cmdsubst" "fail" "$(run_linter "$TMP_DIR/case_in_cmdsubst.sh")"

# The bare word `case`/`esac` as an argument is not the compound command, so
# it must not stop the enclosing `$( )` from closing.
write_fixture "$TMP_DIR/case_as_argument.sh" \
  '#!/usr/bin/env bash' \
  'x="$(echo case)"' \
  'y="$(echo esac; printf %s case; )"' \
  "gh api graphql -f query='query{a{b}}}'"
run_test "case_word_as_argument_does_not_drop_query" "fail" "$(run_linter "$TMP_DIR/case_as_argument.sh")"

# A case subject that itself holds a command substitution still opens a case.
write_fixture "$TMP_DIR/case_subject_cmdsubst.sh" \
  '#!/usr/bin/env bash' \
  "x=\"\$(case \"\$(uname)\" in Darwin) echo m;; esac; gh api graphql -f query='query{a{b}}}')\""
run_test "case_subject_with_cmdsubst_still_tracked" "fail" "$(run_linter "$TMP_DIR/case_subject_cmdsubst.sh")"

write_fixture "$TMP_DIR/tabbed_heredoc.sh" \
  '#!/usr/bin/env bash' \
  'cat <<-EOF' \
  "	it's a body line" \
  '	EOF' \
  "gh api graphql -f query='query{a{b}}}'"
run_test "tab_stripped_heredoc_terminator_found" "fail" "$(run_linter "$TMP_DIR/tabbed_heredoc.sh")"

# Real call-site shapes that do not spell `gh api graphql` on one command
# are still recognised.
write_fixture "$TMP_DIR/wrapper_form.sh" \
  '#!/usr/bin/env bash' \
  'gh_args=(api graphql -f owner="$owner")' \
  "gh \"\${gh_args[@]}\" -f query='query{a{b}}}'"
run_test "wrapper_call_form_still_caught" "fail" "$(run_linter "$TMP_DIR/wrapper_form.sh")"

write_fixture "$TMP_DIR/var_form.sh" \
  '#!/usr/bin/env bash' \
  "  local _gql_items_query='mutation{a(b:1){c}}}'" \
  'gh api graphql -f query="$_gql_items_query"'
run_test "variable_assignment_form_still_caught" "fail" "$(run_linter "$TMP_DIR/var_form.sh")"

# --- Self-check: the real repo tree is currently clean ----------------------

run_test "repo_scripts_tree_is_currently_clean" "pass" "$(run_linter "$REPO_ROOT/scripts")"

echo ""
echo "$PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
