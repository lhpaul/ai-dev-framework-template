#!/usr/bin/env bash
# test-validate-closing-keyword-scope.sh — cross-PR closing-keyword validation
# (issue #1644).
# covers: scripts/development-workflow/validate-closing-keyword-scope.sh
# covers: scripts/development-workflow/closing-keyword-lib.sh
# covers: scripts/development-workflow/post-merge-cleanup.sh
# covers: .github/workflows/closing-keyword-scope.yml
#
# Three kinds of assertion live here, and the difference matters:
#
#   * BEHAVIOUR — the library and the validator's decision logic, exercised
#     directly against stubbed `gh`.
#   * PARITY — the extracted filter must produce byte-identical output to the
#     one post-merge cleanup uses. A reimplementation would be correct on the
#     day it was written and wrong at the first change to either side.
#   * STRUCTURE — assertions on the text of the workflow file. The guards they
#     protect cannot be exercised from a test runner: a fork event cannot be
#     synthesized locally, and GitHub loads pull_request_target workflows from
#     the default branch, so nothing here can make the workflow run. A silently
#     dropped `if:` is exactly the regression that would otherwise ship.
#
# Usage: bash scripts/development-workflow/tests/test-validate-closing-keyword-scope.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
LIB="$REPO_ROOT/scripts/development-workflow/closing-keyword-lib.sh"
VALIDATOR="$REPO_ROOT/scripts/development-workflow/validate-closing-keyword-scope.sh"
CLEANUP="$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/closing-keyword-scope.yml"

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
    echo "FAIL: $name"
    echo "        expected=[$expected]"
    echo "        actual  =[$actual]"
    FAIL=$((FAIL + 1))
  fi
}

check_contains() {
  local name="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "PASS: $name"; PASS=$((PASS + 1)) ;;
    *) echo "FAIL: $name — expected to contain [$needle]"; echo "        actual=[$haystack]"; FAIL=$((FAIL + 1)) ;;
  esac
}

check_not_contains() {
  local name="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "FAIL: $name — expected NOT to contain [$needle]"; FAIL=$((FAIL + 1)) ;;
    *) echo "PASS: $name"; PASS=$((PASS + 1)) ;;
  esac
}

echo "=== test-validate-closing-keyword-scope (#1644) ==="

# shellcheck source=scripts/development-workflow/closing-keyword-lib.sh
. "$LIB"

# ---------------------------------------------------------------------------
# Self-coverage: CI runs a suite only when a changed path matches its
# `# covers:` declarations. A suite that exercises a file it does not declare
# is a suite CI will skip on the very change that breaks it.
# ---------------------------------------------------------------------------

SELECTOR="$REPO_ROOT/scripts/development-workflow/select-test-suites.sh"
SUITE_REL="scripts/development-workflow/tests/test-validate-closing-keyword-scope.sh"
for covered in \
  scripts/development-workflow/validate-closing-keyword-scope.sh \
  scripts/development-workflow/closing-keyword-lib.sh \
  scripts/development-workflow/post-merge-cleanup.sh \
  .github/workflows/closing-keyword-scope.yml
do
  selected="$(printf '%s\n' "$covered" | bash "$SELECTOR" --changed-files - 2>/dev/null || true)"
  case "$selected" in
    *"$SUITE_REL"*) check "self-coverage: $covered selects this suite" "yes" "yes" ;;
    *) check "self-coverage: $covered selects this suite" "yes" "no" ;;
  esac
done

# ---------------------------------------------------------------------------
# Parity: the extracted filter is the one post-merge cleanup uses
#
# Extracted from BOTH files and diffed, rather than asserting on a copy pasted
# here: a test that restated the function would keep passing after either side
# drifted.
# ---------------------------------------------------------------------------

extract_filter() {
  python3 - "$1" <<'PY'
import sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
marker = "strip_fenced_pr_body_blocks() {"
if marker not in text:
    sys.exit(3)
start = text.index(marker)
end = text.index("\n}\n", start) + len("\n}\n")
sys.stdout.write(text[start:end])
PY
}

extract_filter "$LIB" > "$TMP_DIR/lib-filter.txt"
check "the canonical filter lives in the library" "0" "$?"
if extract_filter "$CLEANUP" > "$TMP_DIR/cleanup-filter.txt" 2>/dev/null; then
  check "post-merge-cleanup.sh no longer defines its own copy" "defines-a-copy" "should-not"
else
  check "post-merge-cleanup.sh no longer defines its own copy" "sources-it" "sources-it"
fi
check "post-merge-cleanup.sh sources the library" "yes" \
  "$(grep -q 'closing-keyword-lib.sh' "$CLEANUP" && echo yes || echo no)"

# The regex moved from an inline literal to a shared constant. Its VALUE must
# not have changed in the move: this is what the two parsers agree on.
check "the canonical regex is unchanged by the extraction" \
  '(^|[^[:alnum:]_])(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(issue[[:space:]]+)?#[0-9]+' \
  "$CLOSING_KEYWORD_REGEX"
check "post-merge-cleanup.sh uses the shared constant, not a copy" "yes" \
  "$(grep -q 'grep -ioE "\$CLOSING_KEYWORD_REGEX"' "$CLEANUP" && echo yes || echo no)"
check "no second copy of the keyword literal in post-merge-cleanup.sh" "0" \
  "$(grep -c 'close\[sd\]' "$CLEANUP" || true)"

# Byte-identical output over a corpus that exercises every construct the
# filter knows about.
# The corpus is BUILT rather than written as a heredoc. A heredoc would put
# literal ``` and ~~~ at the start of lines in this file, and
# workflow-shell-snippet-lint.py reads any changed file under
# scripts/development-workflow/ — not only markdown — so it would parse them as
# unmarked shell fences. Assembling the fences from variables keeps the corpus
# exactly as intended without lying to the linter about what this file is.
BT='```'
BT4='````'
TT='~~~'
{
  printf 'Closes #1 at the top\n'
  printf '%s\n' "$BT"
  printf 'Closes #2 inside a fence\n'
  printf '%s\n' "$BT"
  printf 'Closes #3 after the fence\n'
  printf '> Closes #4 in a blockquote\n'
  printf '`Closes #5` in an inline span\n'
  printf '%s\n' "$TT"
  printf 'Closes #6 in a tilde fence\n'
  printf '%s\n' "$TT"
  printf '    %s\n' "$BT"
  printf 'Closes #7 after four-space indent\n'
  printf '   %s\n' "$BT"
  printf 'Closes #8 inside a three-space-indented fence\n'
  printf '   %s\n' "$BT"
  printf 'Closes #9 after it closes\n'
  printf '%s\n' "$BT4"
  printf 'Closes #10 inside a four-backtick fence\n'
  printf '%s\n' "$BT4"
} > "$TMP_DIR/corpus.txt"
lib_out="$(printf '%s' "$(cat "$TMP_DIR/corpus.txt")" | strip_fenced_pr_body_blocks | shasum -a 256 | awk '{print $1}')"
develop_filter="$TMP_DIR/develop-filter.sh"
if git -C "$REPO_ROOT" show "origin/develop:scripts/development-workflow/post-merge-cleanup.sh" > "$TMP_DIR/develop-cleanup.sh" 2>/dev/null; then
  {
    echo '#!/usr/bin/env bash'
    extract_filter "$TMP_DIR/develop-cleanup.sh"
    echo 'strip_fenced_pr_body_blocks'
  } > "$develop_filter"
  develop_out="$(printf '%s' "$(cat "$TMP_DIR/corpus.txt")" | bash "$develop_filter" | shasum -a 256 | awk '{print $1}')"
  check "filter output is byte-identical to post-merge cleanup's (origin/develop)" "$develop_out" "$lib_out"
else
  echo "SKIP: origin/develop unavailable; parity against the pre-extraction copy not checked"
fi

# Non-vacuity: a filter that returned its input unchanged would make every
# parity assertion above pass while proving nothing.
filtered_corpus="$(strip_fenced_pr_body_blocks < "$TMP_DIR/corpus.txt")"
check_not_contains "non-vacuity: the corpus filter actually suppresses a fenced keyword" \
  "Closes #2 inside a fence" "$filtered_corpus"
check_contains "non-vacuity: the corpus filter keeps a live keyword" \
  "Closes #1 at the top" "$filtered_corpus"

# ---------------------------------------------------------------------------
# Which keywords count as live
# ---------------------------------------------------------------------------

refs_of() { printf '%s' "$1" | closing_keyword_live_refs | tr '\n' ' ' | sed 's/ $//'; }

check "boundary_characters_match_and_near_misses_do_not" "12 13 14 15" \
  "$(refs_of 'Closes #12
(Fixes #13)
resolved issue #14
CLOSES #15
Closes#17 has no space')"

# The plan's parser-risk enumeration claimed `Closes #12x` must NOT match. It
# does, and it must: the canonical regex ends at `#[0-9]+` with no trailing
# boundary, so post-merge cleanup — the closer for every pull request merging
# to a non-default branch — reads `Closes #16x` as closing issue 16. The spec
# requires this validation to exclude exactly what the closer excludes, and
# following the plan's claim here would have made the validation silent on a
# reference that really does close a sibling's issue. Parity governs; the plan
# was wrong on this one case, and the PR description says so.
check "trailing_character_after_the_number_still_matches_as_the_closer_does" "16" \
  "$(refs_of 'Closes #16x is still a closing reference to the canonical parser')"
check "substring_lookalikes_not_reported" "" \
  "$(refs_of 'disclose #21 and hotfix #22 and unfixes #23')"
check "multiple_keywords_on_one_line_yield_all" "31 32" \
  "$(refs_of 'Closes #31 and fixes #32')"
check "fenced_keyword_not_reported" "" \
  "$(refs_of '```
Closes #41
```')"
check "blockquoted_keyword_not_reported" "" "$(refs_of '> Closes #42')"
check "inline_span_keyword_not_reported" "" "$(refs_of 'see `Closes #43` here')"
check "unclosed_fence_suppresses_rest" "" \
  "$(refs_of '```
Closes #44
still inside')"
check "nested_backtick_in_tilde_fence" "" \
  "$(refs_of '~~~
```
Closes #45
```
~~~')"
check "longer_closing_fence_closes" "46" \
  "$(refs_of '```
hidden
````
Closes #46')"
check "shorter_closing_fence_does_not_close" "" \
  "$(refs_of '````
hidden
```
Closes #47')"
check "closing_fence_length_at_least_opening" "48" \
  "$(refs_of '```
hidden
```
Closes #48')"
check "three_space_indent_is_a_fence" "" \
  "$(refs_of '   ```
Closes #49')"
check "four_space_indent_is_indented_code" "50" \
  "$(refs_of '    ```
Closes #50')"
check "multiline_inline_span_within_paragraph" "" \
  "$(refs_of 'open `span
Closes #51` close')"
check "paragraph_break_ends_span_scope" "52" \
  "$(refs_of 'open `span

Closes #52')"

# ---------------------------------------------------------------------------
# Differential attribution
#
# These exercise description_live_refs through the validator's own function,
# with the pull request's fields set directly, so the arithmetic being tested
# is the one the validator will run.
# ---------------------------------------------------------------------------

attribute() {
  PR_TITLE="$1" PR_BODY="$2" PR_BASE="$3" DEFAULT_BRANCH="$4" \
  bash -c '
    set -euo pipefail
    . "'"$LIB"'"
    # shellcheck disable=SC1090
    source_validator_functions() {
      # The validator guards its own `main` behind BASH_SOURCE = $0, so
      # sourcing it defines the functions without running anything.
      . "'"$VALIDATOR"'"
    }
    source_validator_functions
    description_live_refs | tr "\n" " " | sed "s/ $//"
  '
}

check "title_only_keyword_not_reported" "" \
  "$(attribute 'Closes #55' 'no keyword in the body' develop main)"
check "description_keyword_is_reported" "77" \
  "$(attribute 'Ordinary title' 'Closes #77' develop main)"
check "title_opens_fence_description_closes_it_later_keyword_is_reported" "12" \
  "$(attribute '```' '```
Closes #12' develop main)"
check "same_issue_live_in_title_and_description_reports_one" "12" \
  "$(attribute 'Closes #12 in the title' 'Closes #12 in the body' develop main)"
# A fence must open at the start of a line, so a suppressing title is one that
# BEGINS with the fence — "title with ```" opens an inline span instead, which
# is a different construct with different rules. The distinction is the reason
# both shapes are tested rather than one.
check "title_fence_suppresses_for_non_default_base" "" \
  "$(attribute '```' 'Closes #61' develop main)"
check "title_fence_does_not_suppress_for_default_base" "61" \
  "$(attribute '```' 'Closes #61' main main)"
check "title_backtick_span_closed_in_the_description_suppresses_what_it_spans" "" \
  "$(attribute 'a title ending in `' 'Closes #63 `' develop main)"
check "the_same_span_does_not_suppress_for_a_default_base" "63" \
  "$(attribute 'a title ending in `' 'Closes #63 `' main main)"
check "hotfix_to_default_base_reads_the_description_alone" "62" \
  "$(attribute '```' 'Closes #62' main main)"

# The mangling's own invariants. If either breaks, attribution stops meaning
# what the difference is supposed to mean.
mangled="$(printf '%s' 'Closes #12 and (Fixes #13) and resolved issue #14' | closing_keyword_mangle)"
check "mangled_keyword_tokens_are_not_keywords" "" \
  "$(printf '%s' "$mangled" | grep -ioE "$CLOSING_KEYWORD_REGEX" | tr '\n' ' ' | sed 's/ $//')"
original='Closes #12 and (Fixes #13) and resolved issue #14'
check "mangling_preserves_text_length_and_filter_output_structure" "${#original}" "${#mangled}"
check_not_contains "mangling does not leave a live keyword" "Closes" "$mangled"
check_contains "mangling leaves the issue number visible for a human" "#12" "$mangled"

# ---------------------------------------------------------------------------
# Ownership
# ---------------------------------------------------------------------------

owners_for() {
  SIBLING_LIST="$1" bash -c '
    set -euo pipefail
    . "'"$LIB"'"
    . "'"$VALIDATOR"'"
    owners_of_issue "'"$2"'" | tr "\n" " " | sed "s/ $//"
  '
}

SIBLINGS='[
  {"number": 101, "headRefName": "fix/97-slug"},
  {"number": 102, "headRefName": "feature/LH-98-slug"},
  {"number": 103, "headRefName": "backport/hotfix/99-slug"},
  {"number": 104, "headRefName": "spec/97-slug"},
  {"number": 105, "headRefName": "implementation-plan/97-slug"},
  {"number": 106, "headRefName": "fix/retro-517-doc-gaps"},
  {"number": 107, "headRefName": "refactor/97-other"}
]'

check "plain_numeric_branch_is_owner" "101 107" "$(owners_for "$SIBLINGS" 97)"
check "team_prefixed_sibling_is_owner" "102" "$(owners_for "$SIBLINGS" 98)"
check "backport_hotfix_branch_is_owner" "103" "$(owners_for "$SIBLINGS" 99)"
check "spec_and_plan_branches_are_never_owners" "101 107" "$(owners_for "$SIBLINGS" 97)"
check "issue_number_in_slug_is_not_ownership" "" "$(owners_for "$SIBLINGS" 517)"
check "no_owner_is_silent_for_that_issue" "" "$(owners_for "$SIBLINGS" 555)"

# ---------------------------------------------------------------------------
# The ordering stamp
# ---------------------------------------------------------------------------

# The validator initialises STAMP_* to empty at load, so the fixture values are
# assigned AFTER sourcing. Setting them in the environment first would leave
# every comparison running against an empty own-stamp, which compares equal to
# nothing and would have made three of these assertions pass for the wrong
# reason.
stamp_later() {
  STAMP_FIXTURE_STARTED="$1" STAMP_FIXTURE_RUN="$2" STAMP_FIXTURE_ATTEMPT="$3" STAMP_FIXTURE_OTHER="$4" bash -c '
    set -euo pipefail
    . "'"$LIB"'"
    . "'"$VALIDATOR"'"
    STAMP_STARTED="$STAMP_FIXTURE_STARTED"
    STAMP_RUN="$STAMP_FIXTURE_RUN"
    STAMP_ATTEMPT="$STAMP_FIXTURE_ATTEMPT"
    if stamp_is_later_than_ours "$STAMP_FIXTURE_OTHER"; then echo later; else echo not-later; fi
  '
}

OURS_TS="2026-09-02T20:00:00.500Z"
check "later_started_blocks_the_write" "later" \
  "$(stamp_later "$OURS_TS" 5 1 "started=2026-09-02T20:00:00.501Z run=1 attempt=1")"
check "earlier_started_does_not_block" "not-later" \
  "$(stamp_later "$OURS_TS" 5 1 "started=2026-09-02T20:00:00.499Z run=9 attempt=9")"
check "equal_started_resolves_to_one_deterministic_winner" "later" \
  "$(stamp_later "$OURS_TS" 5 1 "started=${OURS_TS} run=6 attempt=1")"
check "equal_started_lower_run_does_not_win" "not-later" \
  "$(stamp_later "$OURS_TS" 5 1 "started=${OURS_TS} run=4 attempt=9")"
check "equal_started_and_run_breaks_the_tie_on_attempt" "later" \
  "$(stamp_later "$OURS_TS" 5 1 "started=${OURS_TS} run=5 attempt=2")"
check "identical_stamp_is_not_later_than_itself" "not-later" \
  "$(stamp_later "$OURS_TS" 5 1 "started=${OURS_TS} run=5 attempt=1")"
check "unparseable_stamp_is_adopted_not_frozen" "not-later" \
  "$(stamp_later "$OURS_TS" 5 1 "started=whenever run=x attempt=y")"
check "missing_stamp_is_adopted_not_frozen" "not-later" \
  "$(stamp_later "$OURS_TS" 5 1 "no stamp here at all")"
check "a_stamp_without_milliseconds_is_treated_as_unparseable" "not-later" \
  "$(stamp_later "$OURS_TS" 5 1 "started=2026-09-02T20:00:01Z run=9 attempt=9")"

# The stamp's own generator: fixed width is what makes string comparison
# chronological comparison.
generated="$(closing_keyword_scope_started_at)"
check "started_at_is_fixed_width_iso8601_utc_with_milliseconds" "24" "${#generated}"
check_contains "started_at ends in Z" "Z" "$generated"

# ---------------------------------------------------------------------------
# End to end, against a stubbed `gh`
#
# The stub answers from fixture files, so the whole decision path runs — input
# accessors, indeterminate rule, freshness, publication gating — without
# GitHub.
# ---------------------------------------------------------------------------

STUB_DIR="$TMP_DIR/bin"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# Fixture-backed `gh`. FIXTURES names a directory; each call resolves to a file
# whose first line is an exit code and whose remainder is stdout. A missing
# file is an unreadable input, which is what several assertions need.
set -uo pipefail
key=""
prev=""
case "${1:-}" in
  pr)
    case "${2:-}" in
      view)
        for arg in "$@"; do
          case "$prev" in --json) key="pr_$arg" ;; esac
          prev="$arg"
        done
        ;;
      list) key="pr_list" ;;
    esac
    ;;
  api)
    for arg in "$@"; do
      case "$arg" in
        *"/issues/"*"/comments") key="comments" ;;
        *"check-runs"*) key="check_runs" ;;
        repos/*) [ -n "$key" ] || key="repo" ;;
      esac
    done
    for arg in "$@"; do
      case "$arg" in --method) key="write_${key}" ;; esac
    done
    ;;
  label) key="label_${2:-}" ;;
esac
file="${FIXTURES}/${key}"
if [ ! -f "$file" ]; then
  echo "stub: no fixture for key '${key}' (args: $*)" >&2
  exit 1
fi
code="$(head -1 "$file")"
tail -n +2 "$file"
exit "$code"
STUB
chmod +x "$STUB_DIR/gh"

# jq and shasum are real; only gh is stubbed.
new_fixtures() {
  local dir="$TMP_DIR/fixtures.$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  printf '0\nmain\n' > "$dir/repo"
  printf '0\nlhpaul/ai-dev-framework-template\n' > "$dir/pr_headRepository"
  printf '0\ndeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' > "$dir/pr_headRefOid"
  printf '0\nOrdinary title\n' > "$dir/pr_title"
  printf '0\nCloses #97\n' > "$dir/pr_body"
  printf '0\ndevelop\n' > "$dir/pr_baseRefName"
  printf '0\nfeature/1644-slug\n' > "$dir/pr_headRefName"
  printf '0\nOPEN\n' > "$dir/pr_state"
  printf '0\n\n' > "$dir/pr_labels"
  printf '0\n[{"number":101,"headRefName":"fix/97-slug","title":"t","body":"b","baseRefName":"develop"}]\n' > "$dir/pr_list"
  printf '0\n[]\n' > "$dir/comments"
  printf '0\n[]\n' > "$dir/check_runs"
  printf '%s' "$dir"
}

run_validator() {
  local fixtures="$1"
  shift
  PATH="$STUB_DIR:$PATH" FIXTURES="$fixtures" \
    bash "$VALIDATOR" 42 lhpaul/ai-dev-framework-template "$@" 2>&1 || true
}

verdict_of() { printf '%s\n' "$1" | sed -n 's/^VERDICT=//p' | head -1; }

F="$(new_fixtures warn)"
out="$(run_validator "$F")"
check "a description claiming a sibling's issue warns" "warn" "$(verdict_of "$out")"
check_contains "the report names the issue and the sibling" "| #97 | #101 |" "$out"
check_contains "a non-publishing run says so" "PUBLISHED=false (no --publish)" "$out"

F="$(new_fixtures self)"
printf '0\n[{"number":42,"headRefName":"fix/97-slug","title":"t","body":"b","baseRefName":"develop"}]\n' > "$F/pr_list"
check "self_owned_issue_is_silent" "silent" "$(verdict_of "$(run_validator "$F")")"

F="$(new_fixtures contested)"
printf '0\n[{"number":101,"headRefName":"fix/97-a","title":"t","body":"b","baseRefName":"develop"},{"number":102,"headRefName":"fix/97-b","title":"t","body":"b","baseRefName":"develop"}]\n' > "$F/pr_list"
check "contested_ownership_is_silent" "silent" "$(verdict_of "$(run_validator "$F")")"

F="$(new_fixtures noowner)"
printf '0\n[{"number":101,"headRefName":"fix/555-slug","title":"t","body":"b","baseRefName":"develop"}]\n' > "$F/pr_list"
check "no_owner_is_silent" "silent" "$(verdict_of "$(run_validator "$F")")"

F="$(new_fixtures optout)"
printf '0\nmulti-issue-intentional\n' > "$F/pr_labels"
check "the_opt_out_label_silences_the_warning" "silent" "$(verdict_of "$(run_validator "$F")")"

F="$(new_fixtures nokeyword)"
printf '0\nno closing keyword here\n' > "$F/pr_body"
check "a_pull_request_with_no_closing_keyword_is_silent" "silent" "$(verdict_of "$(run_validator "$F")")"

F="$(new_fixtures closed)"
printf '0\nCLOSED\n' > "$F/pr_state"
check "a_closed_pull_request_is_not_evaluated" "silent" "$(verdict_of "$(run_validator "$F")")"

# --- Non-vacuity of the stub -----------------------------------------------
# Every assertion above would also pass against a stub that answered nothing,
# if the validator treated "nothing" as "silent". It does not, and this proves
# the fixtures are actually being read.
F="$(new_fixtures vacuity)"
rm "$F/pr_body"
out="$(run_validator "$F")"
check "an unreadable description is indeterminate, not silent" "indeterminate" "$(verdict_of "$out")"
check_contains "the indeterminate outcome names what could not be read" "description" "$out"

# --- The indeterminate outcome ---------------------------------------------

for input in description title base_branch labels head_branch default_branch; do
  F="$(new_fixtures "unreadable_${input}")"
  case "$input" in
    description) rm "$F/pr_body" ;;
    title) rm "$F/pr_title" ;;
    base_branch) rm "$F/pr_baseRefName" ;;
    labels) rm "$F/pr_labels" ;;
    head_branch) rm "$F/pr_headRefName" ;;
    default_branch) rm "$F/repo" ;;
  esac
  out="$(run_validator "$F")"
  check "unreadable_${input}_is_indeterminate" "indeterminate" "$(verdict_of "$out")"
  check_contains "unreadable_${input}_is_named_in_the_output" "$input" "$out"
done

F="$(new_fixtures unreadable_pr_list)"
rm "$F/pr_list"
check "unreadable_pr_list_is_indeterminate" "indeterminate" "$(verdict_of "$(run_validator "$F")")"

F="$(new_fixtures unreadable_report)"
rm "$F/comments"
check "unreadable_existing_report_is_indeterminate" "indeterminate" "$(verdict_of "$(run_validator "$F")")"

F="$(new_fixtures unreadable_checks)"
rm "$F/check_runs"
check "unreadable_check_run_list_is_indeterminate" "indeterminate" "$(verdict_of "$(run_validator "$F")")"

F="$(new_fixtures sibling_flag)"
out="$(run_validator "$F" --sibling-list-unreadable)"
check "unreadable_sibling_list_still_validates_the_triggering_pr" "indeterminate" "$(verdict_of "$out")"
check_contains "the sibling-list failure is named as the input it is" "sibling_pull_requests" "$out"

# --- Fork guard ------------------------------------------------------------

F="$(new_fixtures fork)"
printf '0\nsomeone-else/ai-dev-framework-template\n' > "$F/pr_headRepository"
out="$(run_validator "$F")"
check "fork_pr_is_not_validated_and_writes_nothing" "skipped_fork" "$(verdict_of "$out")"
check_not_contains "a fork pull request produces no report row" "| #97 |" "$out"
# With --publish the free context check fires first, so a fork pull request is
# refused twice over. Asserted separately rather than folded into the case
# above: if the guards were ever reordered, one of these two would still fail
# and say which.
out="$(run_validator "$F" --publish)"
check_contains "a fork pull request with --publish is refused before any read" \
  "publication_context_not_serialized" "$out"

# --- Publication gating ----------------------------------------------------

F="$(new_fixtures publish_guard)"
out="$(run_validator "$F" --publish)"
check_contains "publish_without_the_workflow_context_stops" "publication_context_not_serialized" "$out"

F="$(new_fixtures publish_no_flag)"
out="$(run_validator "$F")"
check_contains "invocation_without_publish_writes_nothing" "PUBLISHED=false (no --publish)" "$out"
check_not_contains "a non-publishing run makes no write call" "write_" "$out"

# ---------------------------------------------------------------------------
# Structural assertions on the workflow file
#
# These guard three properties a test runner cannot exercise: a fork event
# cannot be synthesized locally, and GitHub loads pull_request_target workflows
# from the default branch, so nothing here can make the workflow run. Each is
# followed by its PLANTED-VIOLATION PROOF: the same assertion re-run against a
# copy of the shipped workflow with the guard removed, which must fail. An
# assertion that never fails is not evidence that the guard is present.
# ---------------------------------------------------------------------------

assert_fork_if_guard() {
  grep -qE "if:.*head\.repo\.full_name == github\.repository" "$1" \
    || grep -qzE "if: >-[^\"]*head\.repo\.full_name ==\s*github\.repository" "$1"
}

assert_checkout_uses_base_sha() {
  grep -qE 'ref: \$\{\{ github\.event\.pull_request\.base\.sha \}\}' "$1" \
    && ! grep -qE 'pull_request\.head\.sha|refs/pull/' "$1"
}

assert_concurrency_keyed_to_target() {
  grep -qE 'group: closing-keyword-scope-\$\{\{ matrix\.pr \}\}' "$1" \
    && ! grep -qE 'group: closing-keyword-scope-\$\{\{ github\.event\.pull_request\.number' "$1"
}

check "workflow_job_carries_fork_if_guard" "yes" \
  "$(assert_fork_if_guard "$WORKFLOW" && echo yes || echo no)"
check "workflow_checkout_uses_base_sha_never_head" "yes" \
  "$(assert_checkout_uses_base_sha "$WORKFLOW" && echo yes || echo no)"
check "workflow_concurrency_group_is_keyed_to_matrix_target" "yes" \
  "$(assert_concurrency_keyed_to_target "$WORKFLOW" && echo yes || echo no)"

# The writing job must carry the guard itself, not inherit it through `needs:`.
# A guard you have to trace through a dependency chain is a guard someone can
# remove by accident.
validate_job_block="$(awk '/^  validate:/{f=1} f' "$WORKFLOW")"
check "the writing job carries the fork guard itself" "yes" \
  "$(printf '%s' "$validate_job_block" | grep -qE "head\.repo\.full_name ==" && echo yes || echo no)"

# --- Planted-violation proofs (REVIEW.md) -----------------------------------
#
# Each plants ONE violation on a COPY of the shipped workflow — never the
# shipped file — and asserts both directions: the check fails with the
# violation present, and passes once it is removed.

PLANT_DIR="$TMP_DIR/planted"
mkdir -p "$PLANT_DIR"

plant_and_prove() {
  local label="$1" assertion="$2" plant_cmd="$3"
  local copy="$PLANT_DIR/$label.yml"
  cp "$WORKFLOW" "$copy"
  # Sanity: the assertion passes on the faithful copy, so a failure below is
  # the plant and not the copying.
  check "planted-violation baseline: $label passes on an unmodified copy" "yes" \
    "$("$assertion" "$copy" && echo yes || echo no)"
  eval "$plant_cmd"
  check "planted-violation: $label FAILS with the violation present" "no" \
    "$("$assertion" "$copy" && echo yes || echo no)"
  cp "$WORKFLOW" "$copy"
  check "planted-violation: $label passes once the violation is removed" "yes" \
    "$("$assertion" "$copy" && echo yes || echo no)"
}

# 1. Delete the fork `if:` from the validate job.
plant_and_prove "fork_if_guard" assert_fork_if_guard \
  'python3 - "$copy" <<PY
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text()
t = re.sub(r"\n *if: >-\n( *[^\n]*\n)+?(?= *runs-on| *permissions| *strategy)", "\n", t)
t = t.replace("    if: github.event.pull_request.head.repo.full_name == github.repository\n", "")
p.write_text(t)
PY'

# 2. Point the checkout at the pull request head instead of the base.
plant_and_prove "checkout_base_sha" assert_checkout_uses_base_sha \
  'sed -i.bak "s/pull_request\.base\.sha/pull_request.head.sha/" "$copy"'

# 3. Key the concurrency group to the triggering pull request.
plant_and_prove "concurrency_target_key" assert_concurrency_keyed_to_target \
  'sed -i.bak "s/closing-keyword-scope-\${{ matrix\.pr }}/closing-keyword-scope-\${{ github.event.pull_request.number }}/" "$copy"'

# --- The workflow's own routing contract -----------------------------------

check "prs is always emitted, never left unset" "yes" \
  "$(grep -q 'json="\[\]"' "$WORKFLOW" && echo yes || echo no)"
check "nothing_to_validate_emits_an_empty_array_not_an_unset_output" "yes" \
  "$(grep -qE "needs\.resolve-targets\.outputs\.prs != '' &&" "$WORKFLOW" && echo yes || echo no)"
check "resolve-targets writes nothing" "read" \
  "$(awk '/^  resolve-targets:/,/^  validate:/' "$WORKFLOW" | grep -oE 'pull-requests: (read|write)' | head -1 | awk '{print $2}')"
check "the validate job has the write permissions it needs" "yes" \
  "$(awk '/^  validate:/{f=1} f' "$WORKFLOW" | grep -q 'checks: write' && echo yes || echo no)"
check "a closed source pull request is dropped from its own target list" "yes" \
  "$(grep -q 'if \[ "$PR_STATE" = "open" \]; then' "$WORKFLOW" && echo yes || echo no)"
check "the fan-out fires on the three lifecycle actions the spec names" "yes" \
  "$(grep -qE '^\s+opened\|reopened\|closed\)' "$WORKFLOW" && echo yes || echo no)"

# ---------------------------------------------------------------------------
echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
