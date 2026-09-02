#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LINTER="$REPO_ROOT/scripts/lint/workflow-shell-snippet-lint.py"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name expected=$expected actual=$actual"
    FAIL=$((FAIL + 1))
  fi
}

run_fixture() {
  local name="$1" expected="$2" content="$3"
  local doc="docs/workflow/snippet-$name.md"
  local diff="$TMP_DIR/$name.diff"
  mkdir -p "$REPO_ROOT/docs/workflow"
  printf '%s\n' "$content" > "$REPO_ROOT/$doc"
  {
    printf 'diff --git a/%s b/%s\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1,%s @@\n' "$doc" "$doc" "$doc" "$(wc -l < "$REPO_ROOT/$doc" | tr -d ' ')"
    sed 's/^/+/' "$REPO_ROOT/$doc"
  } > "$diff"
  if python3 "$LINTER" --input "$diff" > "$TMP_DIR/$name.out" 2>&1; then
    actual=pass
  else
    actual=fail
  fi
  check "$name" "$expected" "$actual"
  rm -f "$REPO_ROOT/$doc"
}

run_fixture missing_contract fail $'```bash\necho hello\n```'
run_fixture bash_boundary fail $'<!-- workflow-shell-contract: bash -->\n```bash\necho hello\n```'
run_fixture bash_contract_pass pass $'<!-- workflow-shell-contract: bash -->\n```bash\nbash -lc "echo hello"\n```'
run_fixture portable_for fail $'<!-- workflow-shell-contract: bash-zsh -->\n```shell\nfor item in $ITEMS; do echo "$item"; done\n```'
run_fixture portable_set fail $'<!-- workflow-shell-contract: bash-zsh -->\n```shell\nset -- $pair\n```'
run_fixture portable_pass pass $'<!-- workflow-shell-contract: bash-zsh -->\n```shell\nwhile IFS= read -r item; do echo "$item"; done <<EOF\na\nEOF\n```'
run_fixture typed_non_shell_boundary pass $'```text\nstatus only\n```\n\ngit status is referenced in prose, not a snippet.\n\n<!-- workflow-shell-contract: bash-zsh -->\n```bash\necho hello\n```'
run_fixture explicit_ts_tag_ignores_shell_signal pass $'```ts\nexport const DEFAULT_LOCALE = \'es\';\n\nexport function toLocale(code: string | null): string {\n  if (code === null) return DEFAULT_LOCALE;\n  return code;\n}\n```'
run_fixture explicit_typescript_tag_ignores_shell_signal pass $'```typescript\nexport function run(): void {\n  if (true) {\n    console.log("ok");\n  }\n}\n```'
run_fixture explicit_python_tag_ignores_shell_signal pass $'```python\nimport os\n\nif __name__ == "__main__":\n    export = os.environ.get("X")\n```'
run_fixture explicit_sql_tag_ignores_shell_signal pass $'```sql\nfor x in (1, 2, 3) loop\n  set y = x;\nend loop;\n```'
run_fixture untagged_shell_signal_still_flagged fail $'```\ngit status\n```'

contract_doc="docs/workflow/snippet-contract-only.md"
contract_diff="$TMP_DIR/contract-only.diff"
printf '%s\n' '<!-- workflow-shell-contract: bash -->' '```bash' 'echo hello' '```' > "$REPO_ROOT/$contract_doc"
printf '%s\n' "diff --git a/$contract_doc b/$contract_doc" "--- a/$contract_doc" "+++ b/$contract_doc" '@@ -0,0 +1 @@' '+<!-- workflow-shell-contract: bash -->' > "$contract_diff"
if python3 "$LINTER" --input "$contract_diff" > "$TMP_DIR/contract-only.out" 2>&1; then
  contract_only=pass
else
  contract_only=fail
fi
check contract_only_marker fail "$contract_only"
rm -f "$REPO_ROOT/$contract_doc"

# --- Issue #1658: a run that examined nothing must not read as a clean run ---
#
# Every case below distinguishes the three ways "zero examined" can arise:
# a git/subprocess failure, an input that is not a diff at all, and a diff that
# is genuinely empty. Before #1658 all three exited 0 in silence, and a real
# WS002 survived one of them on PR #1646.

run_linter() {
  # Prints "<exit-code>" and leaves combined output in $TMP_DIR/last.out.
  local rc=0
  "$@" > "$TMP_DIR/last.out" 2>&1 || rc=$?
  printf '%s' "$rc"
}

# git exits 1 with no output. Exit 1 is how `git diff --exit-code` reports
# differences, so it must NOT be treated as a subprocess error — but an empty
# diff is still nothing examined, so the refusal is the empty-diff one.
fake_git_dir="$TMP_DIR/fake-git"
mkdir -p "$fake_git_dir"
printf '%s\n' '#!/usr/bin/env sh' 'exit 1' > "$fake_git_dir/git"
chmod +x "$fake_git_dir/git"
check git_exit_one_refused 2 \
  "$(PATH="$fake_git_dir:$PATH" run_linter python3 "$LINTER" --base-ref ignored)"
if grep -q "the diff under examination is empty" "$TMP_DIR/last.out"; then
  check git_exit_one_reason empty_diff empty_diff
else
  check git_exit_one_reason empty_diff "$(head -1 "$TMP_DIR/last.out")"
fi
# ...and --allow-empty is the documented opt-out for exactly that case.
check git_exit_one_allow_empty 0 \
  "$(PATH="$fake_git_dir:$PATH" run_linter python3 "$LINTER" --base-ref ignored --allow-empty)"

# git fails for a real reason: that is a subprocess error, not an empty diff.
fake_git_fail_dir="$TMP_DIR/fake-git-fail"
mkdir -p "$fake_git_fail_dir"
printf '%s\n' '#!/usr/bin/env sh' 'echo "fatal: bad revision" >&2' 'exit 128' > "$fake_git_fail_dir/git"
chmod +x "$fake_git_fail_dir/git"
check git_hard_failure_errors 2 \
  "$(PATH="$fake_git_fail_dir:$PATH" run_linter python3 "$LINTER" --base-ref ignored)"
if grep -q "fatal: bad revision" "$TMP_DIR/last.out"; then
  check git_hard_failure_reason git_error git_error
else
  check git_hard_failure_reason git_error "$(head -1 "$TMP_DIR/last.out")"
fi

# --input given a PATH LIST (the PR #1646 misuse) errors instead of parsing as
# an empty diff. This is the case that produced false WS002-clean evidence.
printf '%s\n' 'scripts/lint/README.md' 'AGENTS.md' > "$TMP_DIR/pathlist.txt"
check path_list_input_errors 2 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/pathlist.txt")"
if grep -q "expects a unified diff" "$TMP_DIR/last.out"; then
  check path_list_input_reason not_a_diff not_a_diff
else
  check path_list_input_reason not_a_diff "$(head -1 "$TMP_DIR/last.out")"
fi
# --allow-empty does not rescue a non-diff input: it is malformed, not empty.
check path_list_input_allow_empty_still_errors 2 \
  "$(run_linter python3 "$LINTER" --input "$TMP_DIR/pathlist.txt" --allow-empty)"

# Empty and whitespace-only inputs are "empty", not "malformed".
: > "$TMP_DIR/empty.diff"
check empty_input_refused 2 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/empty.diff")"
check empty_input_allow_empty 0 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/empty.diff" --allow-empty)"
printf '   \n\t\n' > "$TMP_DIR/blank.diff"
check whitespace_input_refused 2 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/blank.diff")"
if grep -q "the diff under examination is empty" "$TMP_DIR/last.out"; then
  check whitespace_input_reason empty_diff empty_diff
else
  check whitespace_input_reason empty_diff "$(head -1 "$TMP_DIR/last.out")"
fi

# A well-formed diff that touches no in-scope guidance file is a legitimate
# zero: exit 0, but it says so out loud. CI runs --base-ref on every PR and
# most PRs are in exactly this state, so this must not fail closed.
printf '%s\n' 'diff --git a/scripts/lint/x.py b/scripts/lint/x.py' '--- a/scripts/lint/x.py' '+++ b/scripts/lint/x.py' '@@ -0,0 +1 @@' '+print("hi")' > "$TMP_DIR/out-of-scope.diff"
check out_of_scope_diff_passes 0 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/out-of-scope.diff")"
if grep -q "examined=0 files, 0 fences" "$TMP_DIR/last.out" && grep -q "not 'checks passed'" "$TMP_DIR/last.out"; then
  check out_of_scope_diff_summary announced announced
else
  check out_of_scope_diff_summary announced "$(cat "$TMP_DIR/last.out")"
fi

# Diff markers must be the syntax this parser consumes, not a prefix. A stray
# "@@ some prose" line or a Markdown rule is not a diff, and accepting either
# would restore the fail-open path this issue closes.
printf '%s\n' '@@ arbitrary text' 'not a diff at all' > "$TMP_DIR/bogus-marker.diff"
check isolated_marker_not_a_diff 2 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/bogus-marker.diff")"
if grep -q "expects a unified diff" "$TMP_DIR/last.out"; then
  check isolated_marker_reason not_a_diff not_a_diff
else
  check isolated_marker_reason not_a_diff "$(head -1 "$TMP_DIR/last.out")"
fi
printf -- '--- \nsome prose under a Markdown rule\n' > "$TMP_DIR/md-rule.diff"
check markdown_rule_not_a_diff 2 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/md-rule.diff")"

# Diff-shaped but with no target header this parser can read is its own refusal:
# "cannot read it" is not the same claim as "there was nothing in it".
printf '%s\n' 'diff --git docs/workflow/x.md docs/workflow/x.md' '--- docs/workflow/x.md' '+++ docs/workflow/x.md' '@@ -0,0 +1 @@' '+hi' > "$TMP_DIR/no-prefix.diff"
check no_prefix_diff_refused 2 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/no-prefix.diff")"
if grep -q "parser cannot read" "$TMP_DIR/last.out"; then
  check no_prefix_diff_reason unparseable unparseable
else
  check no_prefix_diff_reason unparseable "$(head -1 "$TMP_DIR/last.out")"
fi

# Validation is per record, not global. A diff whose first record is well formed
# would otherwise vouch for a later record this parser cannot read: the markers
# are all present *somewhere*, and changed_lines() would credit the unreadable
# record's lines to the previous record's path.
printf '%s\n' \
  'diff --git a/scripts/lint/x.py b/scripts/lint/x.py' '--- a/scripts/lint/x.py' '+++ b/scripts/lint/x.py' '@@ -0,0 +1 @@' '+print("hi")' \
  'diff --git docs/workflow/ws.md docs/workflow/ws.md' '--- docs/workflow/ws.md' '+++ docs/workflow/ws.md' '@@ -0,0 +1,3 @@' '+```bash' '+echo hello' '+```' \
  > "$TMP_DIR/mixed-records.diff"
check mixed_records_refused 2 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/mixed-records.diff")"
if grep -q "parser cannot read" "$TMP_DIR/last.out"; then
  check mixed_records_reason unparseable unparseable
else
  check mixed_records_reason unparseable "$(head -1 "$TMP_DIR/last.out")"
fi
# ...and the lines of an unreadable record are never credited to the previous
# record's path. Proven directly: put an in-scope, well-formed record FIRST, so
# a leaking parser would attribute the following unreadable record's fence to
# it and report a WS001 against the wrong file at the wrong line.
leak_doc="docs/workflow/snippet-leak-target.md"
mkdir -p "$REPO_ROOT/docs/workflow"
printf '%s\n' 'prose only, no fence here' > "$REPO_ROOT/$leak_doc"
printf '%s\n' \
  "diff --git a/$leak_doc b/$leak_doc" "--- /dev/null" "+++ b/$leak_doc" '@@ -0,0 +1 @@' '+prose only, no fence here' \
  'diff --git docs/workflow/other.md docs/workflow/other.md' '--- docs/workflow/other.md' '+++ docs/workflow/other.md' '@@ -0,0 +1,3 @@' '+```bash' '+echo hello' '+```' \
  > "$TMP_DIR/leak.diff"
check attribution_leak_refused 2 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/leak.diff")"
if grep -q "$leak_doc" "$TMP_DIR/last.out"; then
  check attribution_no_leak no_leak "leaked: $(cat "$TMP_DIR/last.out")"
else
  check attribution_no_leak no_leak no_leak
fi
rm -f "$REPO_ROOT/$leak_doc"

# The refusal above short-circuits before parsing, so assert the parser-level
# property directly: changed_lines() must credit an unreadable record's lines to
# nothing, not to the previous record's path. Without the per-record reset this
# returns {"docs/workflow/first.md": {1, 2, 3, 4}}.
attribution_probe="$(python3 - "$LINTER" <<'PYPROBE'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("snippet_lint", sys.argv[1])
module = importlib.util.module_from_spec(spec)
# @dataclass resolves annotations through sys.modules; register before exec.
sys.modules["snippet_lint"] = module
spec.loader.exec_module(module)
diff = "\n".join([
    "diff --git a/docs/workflow/first.md b/docs/workflow/first.md",
    "--- /dev/null",
    "+++ b/docs/workflow/first.md",
    "@@ -0,0 +1 @@",
    "+prose",
    "diff --git docs/workflow/second.md docs/workflow/second.md",
    "--- docs/workflow/second.md",
    "+++ docs/workflow/second.md",
    "@@ -0,0 +1,3 @@",
    "+```bash",
    "+echo hello",
    "+```",
])
result = module.changed_lines(diff)
print(";".join(f"{path}={sorted(lines)}" for path, lines in sorted(result.items())))
PYPROBE
)"
check attribution_per_record "docs/workflow/first.md=[1]" "$attribution_probe"

# changed_lines() processes the bytes before the first `diff --git` header, so
# the shape check has to cover them too. An unreadable preamble followed by a
# valid metadata-only record must refuse, not pass on the record's strength.
printf '%s\n' '@@ -0,0 +1,3 @@' '+```bash' '+echo hello' '+```' \
  'diff --git a/docs/workflow/a.md b/docs/workflow/a.md' 'old mode 100644' 'new mode 100755' \
  > "$TMP_DIR/unreadable-preamble.diff"
check unreadable_preamble_refused 2 \
  "$(run_linter python3 "$LINTER" --input "$TMP_DIR/unreadable-preamble.diff")"
if grep -q "parser cannot read" "$TMP_DIR/last.out"; then
  check unreadable_preamble_reason unparseable unparseable
else
  check unreadable_preamble_reason unparseable "$(head -1 "$TMP_DIR/last.out")"
fi
# Only a `diff --git`-framed record may legitimately carry neither a hunk nor a
# target header. Prose before one is not a metadata-only record; it is prose.
printf '%s\n' 'just some prose' 'more prose' \
  'diff --git a/docs/workflow/a.md b/docs/workflow/a.md' 'old mode 100644' 'new mode 100755' \
  > "$TMP_DIR/prose-preamble.diff"
check prose_preamble_refused 2 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/prose-preamble.diff")"
check prose_preamble_allow_empty_still_errors 2 \
  "$(run_linter python3 "$LINTER" --input "$TMP_DIR/prose-preamble.diff" --allow-empty)"
if grep -q "text that is not one" "$TMP_DIR/last.out"; then
  check prose_preamble_reason not_a_diff not_a_diff
else
  check prose_preamble_reason not_a_diff "$(head -1 "$TMP_DIR/last.out")"
fi

# A readable preamble — a bare `diff -u` record with no `diff --git` framing —
# is still valid input, and its path is still examined.
printf '%s\n' '--- a/docs/workflow/z.md' '+++ b/docs/workflow/z.md' '@@ -0,0 +1 @@' '+x' \
  'diff --git a/docs/workflow/a.md b/docs/workflow/a.md' 'old mode 100644' 'new mode 100755' \
  > "$TMP_DIR/readable-preamble.diff"
check readable_preamble_passes 0 \
  "$(run_linter python3 "$LINTER" --input "$TMP_DIR/readable-preamble.diff")"
if grep -q "examined=1 files" "$TMP_DIR/last.out"; then
  check readable_preamble_examined announced announced
else
  check readable_preamble_examined announced "$(cat "$TMP_DIR/last.out")"
fi

# A line that merely starts with "diff --git " is not a header: a complete one
# names two paths. Without that check, prose could stand in as evidence of a
# metadata-only Git record and exit 0.
printf '%s\n' 'diff --git notas' 'some prose' > "$TMP_DIR/partial-git-header.diff"
check partial_git_header_refused 2 \
  "$(run_linter python3 "$LINTER" --input "$TMP_DIR/partial-git-header.diff")"
check partial_git_header_allow_empty_still_errors 2 \
  "$(run_linter python3 "$LINTER" --input "$TMP_DIR/partial-git-header.diff" --allow-empty)"
if grep -q "expects a unified diff" "$TMP_DIR/last.out"; then
  check partial_git_header_reason not_a_diff not_a_diff
else
  check partial_git_header_reason not_a_diff "$(head -1 "$TMP_DIR/last.out")"
fi
# A path containing a space is not quoted in this header; the check must still
# accept it.
printf '%s\n' 'diff --git a/docs/workflow/a b.md b/docs/workflow/a b.md' 'old mode 100644' 'new mode 100755' > "$TMP_DIR/spaced-path.diff"
check spaced_path_metadata_only_passes 0 \
  "$(run_linter python3 "$LINTER" --input "$TMP_DIR/spaced-path.diff")"

# A genuine Git record with no textual changes — a mode-only change, a binary
# file, a pure rename — has no hunk and no `+++` header, and there is nothing
# for this parser to attribute. That is a legitimate zero, and refusing it would
# fail CI on any pull request containing one. Built with real git, not by hand,
# so the fixture cannot drift from what git actually emits.
mode_repo="$TMP_DIR/mode-repo"
mkdir -p "$mode_repo/docs/workflow"
(
  cd "$mode_repo"
  git init -q .
  git config user.email test@example.com
  git config user.name Test
  printf 'hi\n' > docs/workflow/a.md
  git add -A
  git commit -q -m seed
  git branch -M develop
  git checkout -q -b feat
  chmod +x docs/workflow/a.md
  git add -A
  git commit -q -m mode-only
)
check mode_only_diff_passes 0 "$(cd "$mode_repo" && run_linter python3 "$LINTER" --base-ref develop)"
if grep -q "examined=0 files, 0 fences" "$TMP_DIR/last.out"; then
  check mode_only_diff_summary announced announced
else
  check mode_only_diff_summary announced "$(cat "$TMP_DIR/last.out")"
fi
(
  cd "$mode_repo"
  printf '\000\001\002' > docs/workflow/b.bin
  git add -A
  git commit -q -m binary
)
check binary_diff_passes 0 "$(cd "$mode_repo" && run_linter python3 "$LINTER" --base-ref develop)"
# ...and out of scope too, which is where most such changes land.
(
  cd "$mode_repo"
  mkdir -p tools
  printf 'x\n' > tools/script.sh
  git add -A
  git commit -q -m seed-out-of-scope
  chmod +x tools/script.sh
  git add -A
  git commit -q -m mode-only-out-of-scope
)
check mode_only_out_of_scope_passes 0 "$(cd "$mode_repo" && run_linter python3 "$LINTER" --base-ref HEAD~1)"

# A hunk with no target header is different: it carries changed lines this
# parser cannot attribute to a path, so it refuses rather than reporting zero.
# A lone target header is the mirror case — a path with no lines behind it.
printf '%s\n' '+++ b/docs/workflow/x.md' > "$TMP_DIR/lone-target.diff"
check lone_target_header_refused 2 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/lone-target.diff")"
if grep -q "parser cannot read" "$TMP_DIR/last.out"; then
  check lone_target_header_reason unparseable unparseable
else
  check lone_target_header_reason unparseable "$(head -1 "$TMP_DIR/last.out")"
fi
# --allow-empty does not rescue a fragment either: it is malformed, not empty.
check lone_target_header_allow_empty_still_errors 2 \
  "$(run_linter python3 "$LINTER" --input "$TMP_DIR/lone-target.diff" --allow-empty)"
printf '%s\n' '@@ -0,0 +1 @@' '+hi' > "$TMP_DIR/lone-hunk.diff"
check lone_hunk_refused 2 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/lone-hunk.diff")"
# A `diff --git` frame does not rescue a target header with no hunk behind it:
# in real output a target header exists to introduce a hunk, so this is a
# fragment, not a metadata-only record.
printf '%s\n' 'diff --git a/docs/workflow/x.md b/docs/workflow/x.md' '--- a/docs/workflow/x.md' '+++ b/docs/workflow/x.md' > "$TMP_DIR/framed-target-no-hunk.diff"
check framed_target_no_hunk_refused 2 \
  "$(run_linter python3 "$LINTER" --input "$TMP_DIR/framed-target-no-hunk.diff")"
check framed_target_no_hunk_allow_empty_still_errors 2 \
  "$(run_linter python3 "$LINTER" --input "$TMP_DIR/framed-target-no-hunk.diff" --allow-empty)"
if grep -q "parser cannot read" "$TMP_DIR/last.out"; then
  check framed_target_no_hunk_reason unparseable unparseable
else
  check framed_target_no_hunk_reason unparseable "$(head -1 "$TMP_DIR/last.out")"
fi

# A deletion-only diff has `+++ /dev/null` and nothing to examine behind it.
# That is a real diff with a legitimate zero, not a malformed one.
printf '%s\n' 'diff --git a/docs/workflow/x.md b/docs/workflow/x.md' 'deleted file mode 100644' '--- a/docs/workflow/x.md' '+++ /dev/null' '@@ -1 +0,0 @@' '-gone' > "$TMP_DIR/deletion.diff"
check deletion_only_diff_passes 0 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/deletion.diff")"

# The summary is printed before EVERY exit, refusals included: a refusal that
# printed only an error would still leave a run with no machine-readable
# statement of how much it examined.
for refusal_case in empty.diff pathlist.txt bogus-marker.diff no-prefix.diff lone-target.diff lone-hunk.diff framed-target-no-hunk.diff partial-git-header.diff mixed-records.diff unreadable-preamble.diff prose-preamble.diff; do
  run_linter python3 "$LINTER" --input "$TMP_DIR/$refusal_case" > /dev/null
  if grep -q "examined=0 files, 0 fences, 0 changed-lines" "$TMP_DIR/last.out"; then
    check "summary_on_refusal_$refusal_case" announced announced
  else
    check "summary_on_refusal_$refusal_case" announced "$(cat "$TMP_DIR/last.out")"
  fi
done
PATH="$fake_git_fail_dir:$PATH" run_linter python3 "$LINTER" --base-ref ignored > /dev/null
if grep -q "examined=0 files, 0 fences, 0 changed-lines" "$TMP_DIR/last.out"; then
  check summary_on_refusal_git_failure announced announced
else
  check summary_on_refusal_git_failure announced "$(cat "$TMP_DIR/last.out")"
fi

# --all is exempt from the empty-diff refusal: it reads no diff, so it can only
# exit 0 (no findings) or 1 (findings), never 2 (nothing examined). It scans the
# whole repository, so the finding count here is whatever the repository holds —
# the assertion is on the refusal path, not on that count.
all_rc="$(run_linter python3 "$LINTER" --all)"
if [ "$all_rc" = "0" ] || [ "$all_rc" = "1" ]; then
  check all_mode_not_refused ok ok
else
  check all_mode_not_refused ok "rc=$all_rc: $(cat "$TMP_DIR/last.out")"
fi
if grep -qE "examined=[1-9][0-9]* files" "$TMP_DIR/last.out"; then
  check all_mode_examined_nonzero ok ok
else
  check all_mode_examined_nonzero ok "$(cat "$TMP_DIR/last.out")"
fi

# The summary line is printed on every run, clean or not, so "exit 0 + silence"
# can no longer exist.
summary_doc="docs/workflow/snippet-summary-clean.md"
mkdir -p "$REPO_ROOT/docs/workflow"
printf '%s\n' '<!-- workflow-shell-contract: bash -->' '```bash' 'bash -lc "echo hello"' '```' > "$REPO_ROOT/$summary_doc"
printf '%s\n' "diff --git a/$summary_doc b/$summary_doc" "--- /dev/null" "+++ b/$summary_doc" '@@ -0,0 +1,4 @@' '+<!-- workflow-shell-contract: bash -->' '+```bash' '+bash -lc "echo hello"' '+```' > "$TMP_DIR/summary-clean.diff"
check summary_clean_exit 0 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/summary-clean.diff")"
if grep -q "examined=1 files, 1 fences" "$TMP_DIR/last.out"; then
  check summary_clean_counts announced announced
else
  check summary_clean_counts announced "$(cat "$TMP_DIR/last.out")"
fi
rm -f "$REPO_ROOT/$summary_doc"

summary_bad_doc="docs/workflow/snippet-summary-finding.md"
printf '%s\n' '```bash' 'echo hello' '```' > "$REPO_ROOT/$summary_bad_doc"
printf '%s\n' "diff --git a/$summary_bad_doc b/$summary_bad_doc" "--- /dev/null" "+++ b/$summary_bad_doc" '@@ -0,0 +1,3 @@' '+```bash' '+echo hello' '+```' > "$TMP_DIR/summary-finding.diff"
check summary_finding_exit 1 "$(run_linter python3 "$LINTER" --input "$TMP_DIR/summary-finding.diff")"
if grep -q "examined=1 files, 1 fences" "$TMP_DIR/last.out" && grep -q "findings=1" "$TMP_DIR/last.out"; then
  check summary_finding_counts announced announced
else
  check summary_finding_counts announced "$(cat "$TMP_DIR/last.out")"
fi
rm -f "$REPO_ROOT/$summary_bad_doc"

# End-to-end through --base-ref against a real repository: a branch carrying a
# known WS002 still fails. This is the documented happy path, and nothing
# covered it before.
e2e_repo="$TMP_DIR/e2e-repo"
mkdir -p "$e2e_repo/docs/workflow"
(
  cd "$e2e_repo"
  git init -q .
  git config user.email test@example.com
  git config user.name Test
  printf 'seed\n' > README.md
  git add README.md
  git commit -q -m seed
  git branch -M develop
  git checkout -q -b feature
  printf '%s\n' '<!-- workflow-shell-contract: bash -->' '```bash' 'echo hello' '```' > docs/workflow/ws002.md
  git add docs/workflow/ws002.md
  git commit -q -m ws002
)
check base_ref_e2e_ws002_fails 1 "$(cd "$e2e_repo" && run_linter python3 "$LINTER" --base-ref develop)"
if grep -q "WS002" "$TMP_DIR/last.out" && grep -q "examined=1 files, 1 fences" "$TMP_DIR/last.out"; then
  check base_ref_e2e_ws002_reason ws002 ws002
else
  check base_ref_e2e_ws002_reason ws002 "$(cat "$TMP_DIR/last.out")"
fi
# Same repo, no new commits on the branch tip vs itself: empty diff, refused.
check base_ref_e2e_empty_refused 2 "$(cd "$e2e_repo" && run_linter python3 "$LINTER" --base-ref feature)"

if ! command -v zsh >/dev/null; then
  echo "FAIL: zsh is required for cross-shell fixture coverage"
  exit 1
fi
expected=$'one\ntwo\nowner repo 7\none\ntwo\nowner repo 7'
actual="$(bash -lc 'bash -lc '\''printf "one\\ntwo\\nowner repo 7\\n"'\''' && zsh -lc 'bash -lc '\''printf "one\\ntwo\\nowner repo 7\\n"'\''')"
check bash_and_zsh_launch_bash "$expected" "$actual"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
