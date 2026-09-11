#!/usr/bin/env bash
# test-select-test-suites.sh - Tests for the CI test-suite selector (issue #1537).
# covers: scripts/development-workflow/select-test-suites.sh
# covers: .github/workflows/workflow-tests.yml

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
SELECTOR="$REPO_ROOT/scripts/development-workflow/select-test-suites.sh"
WORKFLOW_FILE="$REPO_ROOT/.github/workflows/workflow-tests.yml"

# Exact selection counts belong to a fixed repository, not the changing set of
# cross-cutting suites in this checkout. Keep workflow wiring checked against
# the real repository and run selection behavior in this owned fixture.
SOURCE_REPO_ROOT="$REPO_ROOT"
REPO_ROOT="$(mktemp -d)"
cleanup_fixture() {
  chmod -R u+rwX "$REPO_ROOT"
  rm -rf -- "$REPO_ROOT"
}
trap cleanup_fixture EXIT
export SELECT_TEST_SUITES_REPO_ROOT="$REPO_ROOT"
mkdir -p "$REPO_ROOT/scripts/development-workflow/tests"
fixture_suite() {
  local name="$1" coverage="${2:-}"
  printf '#!/usr/bin/env bash\n' > "$REPO_ROOT/scripts/development-workflow/tests/test-$name.sh"
  if [ -n "$coverage" ]; then
    printf '# covers: %s\n' "$coverage" >> "$REPO_ROOT/scripts/development-workflow/tests/test-$name.sh"
  fi
}
for name in run-epic-policy-recommender pr-review-loop workflow-config-resolver \
            add-backlog-item run-epic-risk-classifier run-item-scope-resolver; do
  fixture_suite "$name"
done
for name in changelog-race checkpoints recheck-remaining; do
  fixture_suite "batch-merge-$name" scripts/development-workflow/batch-merge.sh
done
fixture_suite haystack-commit-msg-hook hooks/commit-msg
fixture_suite workflow-hub-product-repo-commands 'scripts/development-workflow/hub-*.sh'
fixture_suite sync-template-apply-modes '.codex/skills/**'
for name in run-epic-policy-recommender pr-review-loop add-backlog-item \
            run-epic-risk-classifier run-item-scope-resolver batch-merge hub-status codex-github-reviewer; do
  printf '#!/usr/bin/env bash\n' > "$REPO_ROOT/scripts/development-workflow/$name.sh"
done
printf '# fixture Python script\n' > "$REPO_ROOT/scripts/development-workflow/workflow-config-resolver.py"

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
# Refuse to overwrite an existing fixture when exercising suite discovery.
if [ -e "$NEW_SUITE" ] || [ -L "$NEW_SUITE" ]; then
  printf 'ERROR: probe path already exists, refusing to overwrite: %s\n' "$NEW_SUITE" >&2
  exit 2
fi
cleanup_probe() { rm -f -- "$NEW_SUITE"; }
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

# Repository integration checks are inclusion-based: additional cross-cutting
# coverage is legitimate and must not make these exact fixture tests brittle.
real_selection="$(printf '%s\n' "$S/resolve-reviewer-availability.sh" \
  | SELECT_TEST_SUITES_REPO_ROOT="$SOURCE_REPO_ROOT" bash "$SELECTOR" --changed-files - 2>/dev/null)"
assert_contains "real_availability_suite_is_selected" "$T/test-resolve-reviewer-availability.sh" "$real_selection"
assert_contains "real_step7a_surface_suite_is_selected" "$T/test-step7a-surface-consistency.sh" "$real_selection"
real_count="$(SELECT_TEST_SUITES_REPO_ROOT="$SOURCE_REPO_ROOT" bash "$SELECTOR" --all | grep -c .)"
real_on_disk="$(find "$SOURCE_REPO_ROOT/$T" -maxdepth 1 -type f -name 'test-*.sh' | wc -l | tr -d ' ')"
run_test "real_all_matches_disk_count" "$real_on_disk" "$real_count"


# Area 11 runs against the real repository so shard packing covers every suite.
REPO_ROOT="$SOURCE_REPO_ROOT"
S="scripts/development-workflow"
T="$S/tests"
unset SELECT_TEST_SUITES_REPO_ROOT
# Area 11: shard packing (#1722)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 11: shard packing ==="

all_suites="$(bash "$SELECTOR" --all)"
all_count="$(printf '%s\n' "$all_suites" | grep -c .)"

shards="$(bash "$SELECTOR" --all --shards 8)"
run_test "shards_emits_requested_count" "8" "$(printf '%s\n' "$shards" | grep -c .)"

# Nothing may be dropped and nothing duplicated: the suites across all shards
# must be exactly the unsharded selection. A packing bug that loses a suite is
# otherwise invisible — the run still goes green, having tested less.
packed="$(printf '%s\n' "$shards" | cut -f2- | tr ' ' '\n' | grep -c . || true)"
run_test "shards_preserve_suite_count" "$all_count" "$packed"
run_test "shards_preserve_exact_set" "same" \
  "$(if [ "$(printf '%s\n' "$shards" | cut -f2- | tr ' ' '\n' | grep . | LC_ALL=C sort)" \
        = "$(printf '%s\n' "$all_suites" | LC_ALL=C sort)" ]; then echo same; else echo differs; fi)"

# No shard may be empty — an empty shard is a job that bills a minute to run
# nothing.
run_test "shards_are_all_non_empty" "0" \
  "$(printf '%s\n' "$shards" | grep -c '	$' || true)"

# Ids are 1-based and name the total, so a job name identifies the shard.
run_test "shards_first_id" "1/8" "$(printf '%s\n' "$shards" | head -1 | cut -f1)"
run_test "shards_last_id" "8/8" "$(printf '%s\n' "$shards" | tail -1 | cut -f1)"

# Deterministic: the packing is an input to a matrix, so the same selection
# must always produce the same shards or a re-run reshuffles the jobs.
run_test "shards_are_deterministic" "same" \
  "$(if [ "$shards" = "$(bash "$SELECTOR" --all --shards 8)" ]; then echo same; else echo differs; fi)"

# Longest-processing-time-first: the slowest declared suite must be placed
# first, and every later suite must go to the least-loaded shard available at
# that moment. This tests the packing rule itself instead of depending on
# today's full-suite inventory having uneven shard sizes.
expected_shards="$(printf '%s\n' "$all_suites" | REPO_ROOT="$REPO_ROOT" SELECTOR="$SELECTOR" python3 -c 'import os, re, sys
repo = os.environ["REPO_ROOT"]
with open(os.environ["SELECTOR"], encoding="utf-8") as selector:
    selector_source = selector.read()
header_lines = int(re.search(r"^COVERS_HEADER_LINES=([0-9]+)$", selector_source, re.M).group(1))
default = int(re.search(r"^DEFAULT_SUITE_SECONDS=([0-9]+)$", selector_source, re.M).group(1))

def suite_duration(suite):
    duration = default
    with open(os.path.join(repo, suite), encoding="utf-8") as handle:
        for _ in range(header_lines):
            line = handle.readline()
            if not line:
                break
            if line.startswith("#") and "duration:" in line:
                token = line.split("duration:", 1)[1].split()
                value = token[0] if token else ""
                if re.fullmatch(r"[0-9]+", value or "") and int(value, 10) > 0:
                    duration = int(value, 10)
                else:
                    duration = default
    return duration

suites = [line.strip() for line in sys.stdin if line.strip()]
ranked = [(-suite_duration(suite), suite) for suite in suites]
bins = [{"load": 0, "suites": []} for _ in range(8)]
for negative_duration, suite in sorted(ranked):
    index = min(range(len(bins)), key=lambda i: (bins[i]["load"], i))
    bins[index]["load"] += -negative_duration
    bins[index]["suites"].append(suite)
for index, shard in enumerate(bins, 1):
    print("%s/8\t%s" % (index, " ".join(shard["suites"])))')"
longest_suite="$(printf '%s\n' "$all_suites" | REPO_ROOT="$REPO_ROOT" SELECTOR="$SELECTOR" python3 -c 'import os, re, sys
repo = os.environ["REPO_ROOT"]
with open(os.environ["SELECTOR"], encoding="utf-8") as selector:
    selector_source = selector.read()
header_lines = int(re.search(r"^COVERS_HEADER_LINES=([0-9]+)$", selector_source, re.M).group(1))
default = int(re.search(r"^DEFAULT_SUITE_SECONDS=([0-9]+)$", selector_source, re.M).group(1))
ranked = []
for suite in [line.strip() for line in sys.stdin if line.strip()]:
    duration = default
    with open(os.path.join(repo, suite), encoding="utf-8") as handle:
        for _ in range(header_lines):
            line = handle.readline()
            if not line:
                break
            if line.startswith("#") and "duration:" in line:
                token = line.split("duration:", 1)[1].split()
                value = token[0] if token else ""
                if re.fullmatch(r"[0-9]+", value or "") and int(value, 10) > 0:
                    duration = int(value, 10)
                else:
                    duration = default
    ranked.append((-duration, suite))
print(sorted(ranked)[0][1])')"
first_actual_suite="$(printf '%s\n' "$shards" | head -1 | cut -f2- | tr ' ' '\n' | head -1)"
run_test "shards_place_longest_suite_first" "$longest_suite" "$first_actual_suite"
run_test "shards_match_lpt_expected" "$expected_shards" "$shards"

# Fewer suites than shards must not emit empty shards.
two="$(printf '%s\n' "$S/run-item-scope-resolver.sh" "$S/run-item-scope-resolver.sh" \
  | bash "$SELECTOR" --changed-files - --shards 8 2>/dev/null)"
run_test "shards_clamp_to_suite_count" "2" "$(printf '%s\n' "$two" | grep -c .)"
run_test "shards_clamp_renumbers_total" "1/2" "$(printf '%s\n' "$two" | head -1 | cut -f1)"

# An empty selection yields no shards at all, so the caller can skip the job.
run_test "shards_empty_selection_lines" "0" \
  "$(printf '%s\n' "random/unmatched.bin" | bash "$SELECTOR" --changed-files - --shards 8 2>/dev/null | grep -c . || true)"
run_test "shards_empty_selection_json" "[]" \
  "$(printf '%s\n' "random/unmatched.bin" | bash "$SELECTOR" --changed-files - --shards 8 --format json 2>/dev/null)"

# JSON is fed straight to fromJSON() in the workflow, where a malformed value
# fails the whole run rather than one job.
shards_json="$(bash "$SELECTOR" --all --shards 8 --format json)"
run_test "shards_json_parses" "8" \
  "$(printf '%s' "$shards_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
run_test "shards_json_keys" "id suites timeout_minutes" \
  "$(printf '%s' "$shards_json" | python3 -c 'import json,sys; print(" ".join(sorted(json.load(sys.stdin)[0])))')"
run_test "shards_json_timeout_scales_by_suite_count" "yes" \
  "$(printf '%s' "$shards_json" | SELECTOR="$SELECTOR" python3 -c 'import json, os, re, sys
with open(os.environ["SELECTOR"], encoding="utf-8") as selector:
    selector_source = selector.read()
default_timeout = int(re.search(r"^SHARD_SUITE_TIMEOUT_SECONDS=\"\$\{SUITE_TIMEOUT_SECONDS:-([0-9]+)\}\"$", selector_source, re.M).group(1))
suite_timeout = int(os.environ.get("SUITE_TIMEOUT_SECONDS", default_timeout))
if (match := re.search(r"^SHARD_TIMEOUT_KILL_AFTER_SECONDS=\"\$\{SUITE_TIMEOUT_KILL_AFTER_SECONDS:-([0-9]+)\}\"$", selector_source, re.M)):
    kill_after = int(os.environ.get("SUITE_TIMEOUT_KILL_AFTER_SECONDS", match.group(1)))
else:
    kill_after = int(re.search(r"^SHARD_TIMEOUT_KILL_AFTER_SECONDS=([0-9]+)$", selector_source, re.M).group(1))
overhead = int(re.search(r"^SHARD_TIMEOUT_OVERHEAD_MINUTES=([0-9]+)$", selector_source, re.M).group(1))
per_suite_timeout = (suite_timeout + kill_after + 59) // 60
ok = True
for shard in json.load(sys.stdin):
    expected = len(shard["suites"].split()) * per_suite_timeout + overhead
    if shard["timeout_minutes"] != expected:
        ok = False
print("yes" if ok else "no")')"

set +e
shards_too_large_out="$(bash "$SELECTOR" --all --shards 1 --format json 2>&1)"
shards_too_large_ec=$?
set -e
oversized_expectations="$(ALL_COUNT="$all_count" SELECTOR="$SELECTOR" python3 -c 'import os, re
with open(os.environ["SELECTOR"], encoding="utf-8") as selector:
    selector_source = selector.read()
default_timeout = int(re.search(r"^SHARD_SUITE_TIMEOUT_SECONDS=\"\$\{SUITE_TIMEOUT_SECONDS:-([0-9]+)\}\"$", selector_source, re.M).group(1))
suite_timeout = int(os.environ.get("SUITE_TIMEOUT_SECONDS", default_timeout))
if (match := re.search(r"^SHARD_TIMEOUT_KILL_AFTER_SECONDS=\"\$\{SUITE_TIMEOUT_KILL_AFTER_SECONDS:-([0-9]+)\}\"$", selector_source, re.M)):
    kill_after = int(os.environ.get("SUITE_TIMEOUT_KILL_AFTER_SECONDS", match.group(1)))
else:
    kill_after = int(re.search(r"^SHARD_TIMEOUT_KILL_AFTER_SECONDS=([0-9]+)$", selector_source, re.M).group(1))
overhead = int(re.search(r"^SHARD_TIMEOUT_OVERHEAD_MINUTES=([0-9]+)$", selector_source, re.M).group(1))
limit = int(re.search(r"^GITHUB_JOB_TIMEOUT_LIMIT_MINUTES=([0-9]+)$", selector_source, re.M).group(1))
per_suite_timeout = (suite_timeout + kill_after + 59) // 60
timeout_minutes = int(os.environ["ALL_COUNT"]) * per_suite_timeout + overhead
print("2 yes" if timeout_minutes > limit else "0 no")')"
run_test "shards_rejects_layout_over_timeout_cap" \
  "$(printf '%s\n' "$oversized_expectations" | cut -d' ' -f1)" "$shards_too_large_ec"
run_test "shards_rejects_layout_over_timeout_cap_message" \
  "$(printf '%s\n' "$oversized_expectations" | cut -d' ' -f2)" \
  "$(printf '%s' "$shards_too_large_out" | grep -q 'exceeding GitHub Actions 360m job timeout cap' && echo yes || echo no)"

# A padded-but-positive shard count must still WORK, not just avoid the octal
# error — the fix normalises rather than rejects, so '08' means 8.
padded_shape="$(printf '%s\n' "$S/run-item-scope-resolver.sh" \
  | bash "$SELECTOR" --changed-files - --shards 08 --format json 2>/dev/null)"
run_test "shards_padded_count_is_sharded_shape" "id suites timeout_minutes" \
  "$(printf '%s' "$padded_shape" | python3 -c 'import json,sys; print(" ".join(sorted(json.load(sys.stdin)[0])))')"

# A suite with no '# duration:' header must still be packed, at the default.
DEFAULT_DURATION_PROBE="$T/test-zzz-default-duration-probe.sh"
if [ -e "$REPO_ROOT/$DEFAULT_DURATION_PROBE" ] || [ -L "$REPO_ROOT/$DEFAULT_DURATION_PROBE" ]; then
  printf 'ERROR: probe path already exists, refusing to overwrite: %s\n' \
    "$REPO_ROOT/$DEFAULT_DURATION_PROBE" >&2
  exit 2
fi
cleanup_default_duration_probe() { rm -f -- "$REPO_ROOT/$DEFAULT_DURATION_PROBE"; }
trap cleanup_default_duration_probe EXIT
printf '#!/usr/bin/env bash\n# covers: scripts/development-workflow/zzz-default-duration-probe.sh\nexit 0\n' \
  > "$REPO_ROOT/$DEFAULT_DURATION_PROBE"
default_duration_out="$(printf '%s\n' scripts/development-workflow/zzz-default-duration-probe.sh \
  | bash "$SELECTOR" --changed-files - --shards 1 2>/dev/null)"
run_test "shards_default_duration_applies" "yes" \
  "$(printf '%s' "$default_duration_out" | grep -q 'test-zzz-default-duration-probe.sh' && echo yes || echo no)"
cleanup_default_duration_probe
trap - EXIT

# Duration hints must be normalised to base 10 at the boundary. A digits-only
# check accepts '08', which bash then reads as octal and dies on with 'value
# too great for base' — taking the whole selection, and therefore the CI gate,
# down over a hint that is only meant to affect shard balance.
DURATION_PROBE="$T/test-zzz-duration-probe.sh"
# Refuse to touch an occupied path, exactly as the unreadable probe above does.
# The selector only discovers suites inside the real tests directory, so the
# probe has to live there — which means this suite writes and then DELETES a
# path in the developer's working tree. Without this guard, someone with
# untracked work at that name loses it to a test run, silently and twice over
# (overwritten in the loop, removed by cleanup).
if [ -e "$REPO_ROOT/$DURATION_PROBE" ] || [ -L "$REPO_ROOT/$DURATION_PROBE" ]; then
  printf 'ERROR: probe path already exists, refusing to overwrite: %s\n' \
    "$REPO_ROOT/$DURATION_PROBE" >&2
  exit 2
fi
cleanup_duration_probe() { rm -f -- "$REPO_ROOT/$DURATION_PROBE"; }
trap cleanup_duration_probe EXIT
for pad in 08 09 007 00 0; do
  printf '#!/usr/bin/env bash\n# duration: %s\n# covers: scripts/development-workflow/zzz-duration-probe.sh\nexit 0\n' \
    "$pad" > "$REPO_ROOT/$DURATION_PROBE"
  set +e
  probe_out="$(printf '%s\n' scripts/development-workflow/zzz-duration-probe.sh | bash "$SELECTOR" --changed-files - --shards 1 2>&1)"
  probe_ec=$?
  set -e
  run_test "duration_zero_padded_${pad}_exit_0" "0" "$probe_ec"
  run_test "duration_zero_padded_${pad}_no_base_error" "no" \
    "$(printf '%s' "$probe_out" | grep -q 'value too great for base' && echo yes || echo no)"
  run_test "duration_zero_padded_${pad}_suite_present" "yes" \
    "$(printf '%s' "$probe_out" | grep -q 'test-zzz-duration-probe.sh' && echo yes || echo no)"
done
cleanup_duration_probe
trap - EXIT

# Argument validation. '00'/'000' are in here because a digits-only check
# accepts them while they are not the literal '0': before the fix they passed
# validation, compared equal to zero downstream, and made the selector emit the
# UNSHARDED shape (an array of strings) where the matrix expects {id, suites}
# objects — a silent wrong answer instead of a usage error.
for bad in 0 00 000 -1 abc ''; do
  set +e
  bash "$SELECTOR" --all --shards "$bad" >/dev/null 2>&1
  ec=$?
  set -e
  run_test "shards_rejects_${bad:-empty}" "2" "$ec"
done

set +e
bash "$SELECTOR" --all --shards >/dev/null 2>&1
ec=$?
set -e
run_test "shards_missing_value_exit_2" "2" "$ec"

# --shards changes the shape of a suite list, so it is meaningless for the
# report modes. Silently ignoring it would hand the caller output it is not
# expecting to parse.
for mode in --report-gaps --print-map; do
  set +e
  bash "$SELECTOR" "$mode" --shards 8 >/dev/null 2>&1
  ec=$?
  set -e
  run_test "shards_rejected_for_${mode#--}" "2" "$ec"
done

# ---------------------------------------------------------------------------
# Area 12: the shard loop's isolation behaviour, executed (#1722)
# ---------------------------------------------------------------------------
#
# Area 10's greps only prove the invocation LOOKS right. This extracts the real
# 'Run shard' step out of the workflow and runs it against synthetic suites, so
# the assertions are about what the loop DOES. It is the difference between a
# check that survives a refactor and one that survives a rewrite.
echo ""
echo "=== Area 12: shard loop isolation (executed) ==="

# Both the outer deadline below and the extracted step's own invocation need
# GNU timeout, which stock macOS does not ship — this suite runs locally as
# well as in CI, so an unguarded dependency would make the documented full
# local harness fail at 127 before testing anything. Same handling as
# resilient_timeout() in local-ai-reviewer.sh: probe for --kill-after support
# rather than trusting the name, and accept Homebrew's 'gtimeout' too.
# The extraction below parses the workflow YAML, which needs PyYAML. CI
# provisions it explicitly in the shard job, but a local host is not required to
# have it — and an unguarded import here fails as "could not read the step",
# which points at the workflow rather than at the missing module.
SHARD_PROBE_YAML=no
if python3 -c 'import yaml' >/dev/null 2>&1; then
  SHARD_PROBE_YAML=yes
fi

SHARD_PROBE_TIMEOUT=""
SHARD_PROBE_TIMEOUT_ABS=""
for candidate in timeout gtimeout; do
  if command -v "$candidate" >/dev/null 2>&1 \
    && "$candidate" --help 2>&1 | grep -q -- '--kill-after'; then
    SHARD_PROBE_TIMEOUT="$candidate"
    # Absolute path, so neither the shim below nor anything else on PATH can
    # shadow it back onto itself.
    SHARD_PROBE_TIMEOUT_ABS="$(command -v "$candidate")"
    break
  fi
done

SHARD_PROBE_DIR="$(mktemp -d)"
cleanup_shard_probe() { rm -rf -- "$SHARD_PROBE_DIR"; }
trap cleanup_shard_probe EXIT

if [ -z "$SHARD_PROBE_TIMEOUT" ] || [ "$SHARD_PROBE_YAML" = no ]; then
  # Skipped rather than failed, and loudly: the properties are still covered by
  # the comment-stripped structural assertions above and by every CI run, which
  # always has both GNU timeout and a provisioned PyYAML. Name the missing
  # dependency — "skipped" without a reason is indistinguishable from "quietly
  # not testing this any more".
  probe_missing=""
  [ -z "$SHARD_PROBE_TIMEOUT" ] && probe_missing="GNU timeout (install coreutils)"
  if [ "$SHARD_PROBE_YAML" = no ]; then
    [ -n "$probe_missing" ] && probe_missing="$probe_missing and "
    probe_missing="${probe_missing}PyYAML (pip install PyYAML)"
  fi
  echo "SKIP: shard loop isolation — missing $probe_missing"
# Pull the step's script out of the YAML rather than duplicating it here: a
# copy would drift, and then this suite would be testing its own replica.
elif python3 - "$WORKFLOW_FILE" "$SHARD_PROBE_DIR/step.sh" <<'EXTRACT'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = wf["jobs"]["test"]["steps"]
run = [s["run"] for s in steps if str(s.get("name", "")).startswith("Run shard")]
if len(run) != 1:
    raise SystemExit(f"expected exactly one 'Run shard' step, found {len(run)}")
open(sys.argv[2], "w").write(run[0])
EXTRACT
then
  printf '#!/usr/bin/env bash\necho hanging; sleep 120\n' > "$SHARD_PROBE_DIR/s_hang.sh"
  printf '#!/usr/bin/env bash\necho failing; exit 1\n'    > "$SHARD_PROBE_DIR/s_fail.sh"
  printf '#!/usr/bin/env bash\nexit 124\n'                > "$SHARD_PROBE_DIR/s_124.sh"
  printf '#!/usr/bin/env bash\nkill -9 "$$"\n'            > "$SHARD_PROBE_DIR/s_kill.sh"
  printf '#!/usr/bin/env bash\necho passing\n'            > "$SHARD_PROBE_DIR/s_pass.sh"
  cat > "$SHARD_PROBE_DIR/s_leak.sh" <<'LEAK'
#!/usr/bin/env bash
(trap '' TERM; sleep 120) &
echo "$!" > leak-child.pid
wait
LEAK

  # The hang is first on purpose: if the per-suite timeout is ever removed,
  # nothing after it would run. The outer 'timeout 90' keeps that regression a
  # test failure rather than a hung CI job.
  set +e
  ( cd "$SHARD_PROBE_DIR" \
    && PATH="$SHARD_PROBE_DIR/bin:$PATH" \
	       GITHUB_STEP_SUMMARY="$SHARD_PROBE_DIR/summary.md" \
	       SHARD_ID="probe" \
	       SHARD_SUITES="s_hang.sh s_fail.sh s_124.sh s_kill.sh s_pass.sh s_leak.sh" \
	       SUITE_TIMEOUT_SECONDS=3 \
	       SUITE_TIMEOUT_KILL_AFTER_SECONDS=1 \
	       "$SHARD_PROBE_TIMEOUT_ABS" 90 bash -eo pipefail "$SHARD_PROBE_DIR/step.sh" ) \
    > "$SHARD_PROBE_DIR/out.txt" 2>&1
  shard_ec=$?
  set -e
  shard_summary="$(cat "$SHARD_PROBE_DIR/summary.md" 2>/dev/null || true)"

  run_test "shard_loop_exits_nonzero" "1" "$shard_ec"

  # Hang isolation: the hung suite is bounded and labelled as a TIMEOUT, not
  # folded into a generic failure.
  run_test "shard_loop_reports_timeout" "yes" \
    "$(printf '%s' "$shard_summary" | grep -q 's_hang.sh.*TIMEOUT' && echo yes || echo no)"

  # ...and the suites AFTER the hang still ran. This is the property a
  # shard-level timeout-minutes cannot provide.
  run_test "shard_loop_runs_suites_after_hang" "yes" \
    "$(printf '%s' "$shard_summary" | grep -q 's_pass.sh.*pass' && echo yes || echo no)"

  # Failure isolation: a failing suite is labelled FAIL and does not abort the
  # loop, which is what GitHub's inherited 'bash -e' would otherwise do.
  run_test "shard_loop_reports_fail" "yes" \
    "$(printf '%s' "$shard_summary" | grep -q 's_fail.sh.*FAIL' && echo yes || echo no)"
  run_test "shard_loop_reports_sigkill_as_fail" "yes" \
    "$(printf '%s' "$shard_summary" | grep -q 's_kill.sh.*FAIL' && echo yes || echo no)"
  run_test "shard_loop_reports_command_124_as_fail" "yes" \
    "$(printf '%s' "$shard_summary" | grep -q 's_124.sh.*FAIL' && echo yes || echo no)"
  run_test "shard_loop_runs_all_six_suites" "6" \
    "$(printf '%s' "$shard_summary" | grep -c '^| `s_' || true)"
  if [ -s "$SHARD_PROBE_DIR/leak-child.pid" ]; then
    leak_pid="$(cat "$SHARD_PROBE_DIR/leak-child.pid")"
    if kill -0 "$leak_pid" 2>/dev/null; then
      leak_alive=yes
      kill "$leak_pid" 2>/dev/null || true
      sleep 0.1
      kill -9 "$leak_pid" 2>/dev/null || true
    else
      leak_alive=no
    fi
  else
    leak_alive=missing
  fi
  run_test "shard_loop_kills_timeout_descendants" "no" "$leak_alive"

  shard_output="$(cat "$SHARD_PROBE_DIR/out.txt" 2>/dev/null || true)"
  run_test "shard_loop_stderr_names_timeout_suite" "yes" \
    "$(printf '%s' "$shard_output" | grep -q 's_hang.sh: \*\*TIMEOUT\*\*' && echo yes || echo no)"
  run_test "shard_loop_stderr_names_failed_suite" "yes" \
    "$(printf '%s' "$shard_output" | grep -q 's_fail.sh: \*\*FAIL\*\*' && echo yes || echo no)"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "FAIL: shard_loop_step_extractable — could not read the 'Run shard' step from $WORKFLOW_FILE"
fi

cleanup_shard_probe
trap - EXIT

# ---------------------------------------------------------------------------
echo ""
echo "────────────────────────────────────────────────────────────"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "────────────────────────────────────────────────────────────"
[ "$FAIL_COUNT" -eq 0 ]
