#!/usr/bin/env bash
# test-select-test-suites.sh - Tests for the CI test-suite selector (issue #1537).
# covers: scripts/development-workflow/select-test-suites.sh
# covers: .github/workflows/workflow-tests.yml

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
SELECTOR="$REPO_ROOT/scripts/development-workflow/select-test-suites.sh"
WORKFLOW_FILE="$REPO_ROOT/.github/workflows/workflow-tests.yml"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS: $name"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "FAIL: $name — expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if grep -qxF -- "$needle" <<<"$haystack"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS: $name"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "FAIL: $name — '$needle' not present in output"
  fi
}

assert_not_contains() {
  local name="$1" needle="$2" haystack="$3"
  if grep -qxF -- "$needle" <<<"$haystack"; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "FAIL: $name — '$needle' unexpectedly present in output"
  else
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS: $name"
  fi
}

# select <changed paths...> — run the selector over an ad-hoc change set.
select_for() {
  printf '%s\n' "$@" | bash "$SELECTOR" --changed-files - 2>/dev/null
}

T="scripts/development-workflow/tests"
S="scripts/development-workflow"

# ---------------------------------------------------------------------------
# Area 1: convention mapping — test-<name>.sh covers <name>.sh
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 1: naming-convention mapping ==="

out="$(select_for "$S/run-epic-policy-recommender.sh")"
assert_contains "convention_selects_matching_suite" \
  "$T/test-run-epic-policy-recommender.sh" "$out"

# AC-5's motivating case: changing one script must not drag in the whole set.
assert_not_contains "convention_excludes_unrelated_suite" \
  "$T/test-pr-review-loop.sh" "$out"
run_test "convention_selects_exactly_one" "1" "$(printf '%s\n' "$out" | grep -c .)"

# A .py script maps the same way.
out="$(select_for "$S/workflow-config-resolver.py")"
assert_contains "convention_maps_python_script" \
  "$T/test-workflow-config-resolver.sh" "$out"

# ---------------------------------------------------------------------------
# Area 2: self-declaration via '# covers:' headers
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2: '# covers:' self-declaration ==="

# batch-merge.sh maps to no suite by name; three suites declare it.
out="$(select_for "$S/batch-merge.sh")"
assert_contains "covers_selects_changelog_race" \
  "$T/test-batch-merge-changelog-race.sh" "$out"
assert_contains "covers_selects_checkpoints" \
  "$T/test-batch-merge-checkpoints.sh" "$out"
assert_contains "covers_selects_recheck_remaining" \
  "$T/test-batch-merge-recheck-remaining.sh" "$out"

# A non-script surface (a git hook) maps through '# covers:' too.
out="$(select_for "hooks/commit-msg")"
assert_contains "covers_selects_commit_msg_hook" \
  "$T/test-haystack-commit-msg-hook.sh" "$out"

# A glob in a '# covers:' line matches.
out="$(select_for "$S/hub-status.sh")"
assert_contains "covers_glob_selects_hub_commands" \
  "$T/test-workflow-hub-product-repo-commands.sh" "$out"

# ---------------------------------------------------------------------------
# Area 3: editing a suite runs that suite
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 3: a suite always covers itself ==="

out="$(select_for "$T/test-add-backlog-item.sh")"
assert_contains "suite_edit_runs_itself" "$T/test-add-backlog-item.sh" "$out"
run_test "suite_edit_runs_only_itself" "1" "$(printf '%s\n' "$out" | grep -c .)"

# ---------------------------------------------------------------------------
# Area 4: full-run triggers
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 4: full-run triggers ==="

total_suites="$(bash "$SELECTOR" --all | grep -c .)"

for trigger in "$S/workflow-lib.sh" "$S/select-test-suites.sh" \
               ".github/workflows/workflow-tests.yml" \
               "$T/fixtures/workflow-hub-smoke/repo.json"; do
  count="$(select_for "$trigger" | grep -c .)"
  run_test "full_run_trigger_$(basename "$trigger")" "$total_suites" "$count"
done

# A non-trigger change does NOT run everything.
count="$(select_for "$S/run-epic-risk-classifier.sh" | grep -c .)"
if [ "$count" -lt "$total_suites" ]; then
  PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: non_trigger_is_scoped"
else
  FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: non_trigger_is_scoped — selected all $count suites"
fi

# ---------------------------------------------------------------------------
# Area 5: no match selects nothing (and is not an error)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 5: unmatched changes ==="

set +e
out="$(select_for "README.md" "CHANGELOG.md")"
ec=$?
set -e
run_test "unmatched_exit_code" "0" "$ec"
run_test "unmatched_selects_nothing" "0" "$(printf '%s\n' "$out" | grep -c .)"

# ---------------------------------------------------------------------------
# Area 6: --all and every suite is reachable
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 6: --all enumerates the tests directory ==="

on_disk="$(find "$REPO_ROOT/$T" -maxdepth 1 -type f -name 'test-*.sh' | wc -l | tr -d ' ')"
run_test "all_matches_disk_count" "$on_disk" "$total_suites"

# AC-2: a suite dropped into the directory is picked up with no workflow edit.
NEW_SUITE="$REPO_ROOT/$T/test-zzz-ac2-probe.sh"
# This probe writes into the real tests directory, so refuse to run if anything
# already occupies that path rather than clobbering a developer's file.
if [ -e "$NEW_SUITE" ] || [ -L "$NEW_SUITE" ]; then
  printf 'ERROR: probe path already exists, refusing to overwrite: %s\n' "$NEW_SUITE" >&2
  exit 2
fi
cleanup_probe() { rm -f -- "$NEW_SUITE"; }
trap cleanup_probe EXIT
cat > "$NEW_SUITE" <<'PROBE'
#!/usr/bin/env bash
# test-zzz-ac2-probe.sh - temporary probe suite.
# covers: scripts/development-workflow/zzz-ac2-probe.sh
set -euo pipefail
PROBE
assert_contains "ac2_new_suite_in_all" "$T/test-zzz-ac2-probe.sh" "$(bash "$SELECTOR" --all)"
assert_contains "ac2_new_suite_selected_by_covers" "$T/test-zzz-ac2-probe.sh" \
  "$(select_for "$S/zzz-ac2-probe.sh")"
cleanup_probe
trap - EXIT
assert_not_contains "ac2_probe_removed" "$T/test-zzz-ac2-probe.sh" "$(bash "$SELECTOR" --all)"

# ---------------------------------------------------------------------------
# Area 7: AC-3 gap report
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 7: AC-3 coverage-gap report ==="

set +e
gaps="$(bash "$SELECTOR" --report-gaps)"
ec=$?
set -e
run_test "gaps_exit_code_zero" "0" "$ec"

uncovered="$(printf '%s\n' "$gaps" | sed -n 's/^UNCOVERED_SCRIPT_COUNT=//p')"
unreachable="$(printf '%s\n' "$gaps" | sed -n 's/^UNREACHABLE_SUITE_COUNT=//p')"
total_scripts="$(printf '%s\n' "$gaps" | sed -n 's/^TOTAL_SCRIPT_COUNT=//p')"

case "$uncovered" in
  ''|*[!0-9]*) run_test "gaps_uncovered_is_numeric" "numeric" "$uncovered" ;;
  *) run_test "gaps_uncovered_is_numeric" "numeric" "numeric" ;;
esac
case "$total_scripts" in
  ''|*[!0-9]*) run_test "gaps_total_is_numeric" "numeric" "$total_scripts" ;;
  *) run_test "gaps_total_is_numeric" "numeric" "numeric" ;;
esac

# Every suite must be reachable from some PR change set. This is the regression
# guard for the '# covers:' headers: adding a suite that no change set can
# select would silently reintroduce the issue-#1537 failure mode for that file.
run_test "gaps_no_unreachable_suites" "0" "$unreachable"

# A known-uncovered script is named in the report rather than passed over.
assert_contains "gaps_names_uncovered_script" \
  "  scripts/development-workflow/codex-github-reviewer.sh" "$gaps"

# ---------------------------------------------------------------------------
# Area 7b: an unreadable suite is fatal, never a silent convention fallback
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 7b: unreadable suite fails hard ==="

# Regression guard. `die` cannot abort the program from inside a process
# substitution, so an unreadable suite used to print ERROR: to stderr and still
# exit 0 — selecting via the naming convention as though nothing had gone
# wrong. A selector that under-selects while reporting success is the exact
# failure this whole script exists to end, so every mode must exit 2.
UNREADABLE="$REPO_ROOT/$T/test-zzz-unreadable-probe.sh"
if [ -e "$UNREADABLE" ] || [ -L "$UNREADABLE" ]; then
  printf 'ERROR: probe path already exists, refusing to overwrite: %s\n' "$UNREADABLE" >&2
  exit 2
fi
cleanup_unreadable() { chmod u+rw -- "$UNREADABLE" 2>/dev/null || true; rm -f -- "$UNREADABLE"; }
trap cleanup_unreadable EXIT
printf '#!/usr/bin/env bash\n# covers: scripts/development-workflow/zzz-unreadable-probe.sh\n' \
  > "$UNREADABLE"
chmod 000 "$UNREADABLE"

if [ -r "$UNREADABLE" ]; then
  # Running as root (or on a filesystem ignoring the mode bits) makes the file
  # readable regardless, so the assertions below would prove nothing.
  echo "SKIP: unreadable-suite checks — the probe is still readable in this environment"
else
  set +e
  bash "$SELECTOR" --all >/dev/null 2>&1; ec_all=$?
  bash "$SELECTOR" --report-gaps >/dev/null 2>&1; ec_gaps=$?
  bash "$SELECTOR" --print-map >/dev/null 2>&1; ec_map=$?
  printf '%s\n' "README.md" | bash "$SELECTOR" --changed-files - >/dev/null 2>&1; ec_changed=$?
  err_text="$(bash "$SELECTOR" --all 2>&1 >/dev/null)"
  set -e
  run_test "unreadable_suite_all_exit_2" "2" "$ec_all"
  run_test "unreadable_suite_gaps_exit_2" "2" "$ec_gaps"
  run_test "unreadable_suite_map_exit_2" "2" "$ec_map"
  run_test "unreadable_suite_changed_exit_2" "2" "$ec_changed"
  run_test "unreadable_suite_reports_error" "yes" \
    "$(printf '%s' "$err_text" | grep -q 'cannot read test suite' && echo yes || echo no)"
fi

cleanup_unreadable
trap - EXIT

# ---------------------------------------------------------------------------
# Area 8: glob semantics
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 8: glob semantics ==="

# '*' must not cross a '/' boundary: the hub-*.sh declaration must not pull in
# a same-named file under tests/.
map="$(bash "$SELECTOR" --print-map)"
hub_map_line="$(printf '%s\t%s' \
  "$T/test-workflow-hub-product-repo-commands.sh" "$S/hub-*.sh")"
assert_contains "map_includes_hub_glob" "$hub_map_line" "$map"

out="$(select_for "$S/tests/hub-not-a-real-file.sh")"
assert_not_contains "star_does_not_cross_slash" \
  "$T/test-workflow-hub-product-repo-commands.sh" "$out"

# '**' does cross '/'.
out="$(select_for ".codex/skills/workflow-sync-template/SKILL.md")"
assert_contains "doublestar_crosses_slash" \
  "$T/test-sync-template-apply-modes.sh" "$out"

# ---------------------------------------------------------------------------
# Area 9: output formats and argument handling
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 9: formats and arguments ==="

json="$(printf '%s\n' "$S/run-item-scope-resolver.sh" \
  | bash "$SELECTOR" --changed-files - --format json 2>/dev/null)"
run_test "json_format_output" \
  "[\"$T/test-run-item-scope-resolver.sh\"]" "$json"

json_empty="$(printf '%s\n' "README.md" \
  | bash "$SELECTOR" --changed-files - --format json 2>/dev/null)"
run_test "json_format_empty" "[]" "$json_empty"

set +e
bash "$SELECTOR" --nope >/dev/null 2>&1
ec=$?
set -e
run_test "unknown_argument_exit_2" "2" "$ec"

set +e
bash "$SELECTOR" >/dev/null 2>&1
ec=$?
set -e
run_test "no_mode_exit_2" "2" "$ec"

set +e
bash "$SELECTOR" --changed-files /nonexistent/path >/dev/null 2>&1
ec=$?
set -e
run_test "missing_changed_files_exit_2" "2" "$ec"

set +e
bash "$SELECTOR" --all --format bogus >/dev/null 2>&1
ec=$?
set -e
run_test "bad_format_exit_2" "2" "$ec"

# Leading './' in a diff path is tolerated.
out="$(select_for "./$S/run-epic-risk-classifier.sh")"
assert_contains "leading_dot_slash_normalised" \
  "$T/test-run-epic-risk-classifier.sh" "$out"

# ---------------------------------------------------------------------------
# Area 10: the workflow file consumes the selector
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 10: workflow wiring ==="

if [ -f "$WORKFLOW_FILE" ]; then
  run_test "workflow_exists" "yes" "yes"
  for needle in "select-test-suites.sh" "--report-gaps" "schedule:" "workflow_dispatch:"; do
    if grep -qF -- "$needle" "$WORKFLOW_FILE"; then
      PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: workflow_has_$needle"
    else
      FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: workflow_has_$needle — not found"
    fi
  done
  # The hard-coded per-suite 'run:' steps this issue removed must not come back.
  hardcoded="$(grep -cE '^\s+run: bash scripts/development-workflow/tests/test-' "$WORKFLOW_FILE" || true)"
  run_test "workflow_has_no_hardcoded_suite_steps" "0" "$hardcoded"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "FAIL: workflow_exists — $WORKFLOW_FILE not found"
fi

# ---------------------------------------------------------------------------
echo ""
echo "────────────────────────────────────────────────────────────"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "────────────────────────────────────────────────────────────"
[ "$FAIL_COUNT" -eq 0 ]
