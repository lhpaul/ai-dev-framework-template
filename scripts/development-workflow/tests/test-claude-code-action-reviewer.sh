#!/usr/bin/env bash
# test-claude-code-action-reviewer.sh — Unit tests for the run-poll jq filter
# logic in claude-code-action-reviewer.sh.
#
# Tests verify that the run-name PR-scoped filter (post-#806/#808 fix) selects
# the correct run from the GitHub Actions Runs API response. Area 3 verifies
# that inputs.pr_number (always null in the API) is not referenced. Areas 5+
# verify the run-name PR-scoping mechanism required for concurrent dispatch:
# under parallel batches, two PRs may dispatch claude-code-review.yml within
# the same poll window; the run-name filter ensures only the run for THIS PR
# is selected, not the most-recent run regardless of which PR triggered it.
#
# Usage: bash scripts/development-workflow/tests/test-claude-code-action-reviewer.sh
# Requires: bash, jq
# Exit code: 0 if all tests pass, 1 if any test fails.

set -euo pipefail

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# The run-poll jq filter (extracted verbatim from claude-code-action-reviewer.sh)
# Arguments: $wf (workflow filename suffix), $poll_after (ISO8601 timestamp),
#            $pr (PR number string for run-name scoping)
# ---------------------------------------------------------------------------
RUN_POLL_FILTER='# Candidate set: workflow-file + timestamp match
         [.[] | .workflow_runs[]?] as $all |
         [$all[] | select((.path | endswith($wf)) and .created_at >= $poll_after)] as $candidates |
         # PR-scoping via run-name (#808): if any candidate has a "PR #N"-style name
         # (indicating the workflow uses run-name), require name match for THIS PR to
         # prevent selecting the wrong PR'\''s run under concurrent/parallel dispatch.
         # Fall back to all candidates when no run has the "PR #N" pattern — backward
         # compat with pre-#808 deployments where the workflow has no run-name yet.
         ([$candidates[] | select((.name // "") | capture("PR #(?<pr>[0-9]+)(?:[^0-9]|$)")?)] | length > 0) as $name_scoped |
         ($candidates | if $name_scoped then
           [.[] | select(((.name // "") | capture("PR #(?<pr>[0-9]+)(?:[^0-9]|$)")? | .pr) == $pr)]
         else . end) |
         sort_by(.created_at) | reverse | first |
         {status: .status, conclusion: .conclusion, html_url: .html_url, id: .id}'

run_filter() {
  local json="$1" wf="$2" poll_after="$3" pr="${4:-808}"
  printf '%s\n' "$json" | jq -r \
    --slurp \
    --arg wf "$wf" \
    --arg poll_after "$poll_after" \
    --arg pr "$pr" \
    "$RUN_POLL_FILTER"
}

# ---------------------------------------------------------------------------
# Area 1: Basic timestamp filtering
# Run objects include "name" matching the dispatched PR (808) so they pass the
# run-name PR-scoping filter added in #808.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 1: timestamp filtering ==="

# Test 1.1: A single matching run is selected
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://github.com/owner/repo/actions/runs/100","id":100}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "single_match_selected" "100" "$_id"
unset _json _result _id

# Test 1.2: A run before poll_after is excluded — filter returns object with null id
# When the filtered array is empty, jq `first` on [] returns null; piping through
# `| {id: .id}` yields {"id":null}. The script treats this as "no match found"
# via the `RUN_STATUS=$(... '.status // empty')` guard (empty string → loop continues).
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T15:58:00Z","status":"completed","conclusion":"success","html_url":"https://github.com/owner/repo/actions/runs/99","id":99}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id // "null"')
run_test "old_run_excluded_null_id" "null" "$_id"
unset _json _result _id

# Test 1.3: Multiple runs for same PR — most recent is selected
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:01:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":200},{"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://b","id":100}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "most_recent_selected" "200" "$_id"
unset _json _result _id

# Test 1.4: Empty workflow_runs → no match (id field is null)
_json='{"workflow_runs":[]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id // "null"')
run_test "empty_list_null_id" "null" "$_id"
unset _json _result _id

# ---------------------------------------------------------------------------
# Area 2: Workflow file path matching
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2: workflow file path matching ==="

# Test 2.1: A run with a different workflow file is excluded (id field is null)
_json='{"workflow_runs":[{"path":".github/workflows/other-workflow.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":300}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id // "null"')
run_test "different_workflow_excluded_null_id" "null" "$_id"
unset _json _result _id

# Test 2.2: Mixed runs — only the matching workflow file is selected
_json='{"workflow_runs":[{"path":".github/workflows/other-workflow.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:01:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":400},{"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://b","id":401}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "correct_workflow_selected_from_mixed" "401" "$_id"
unset _json _result _id

# ---------------------------------------------------------------------------
# Area 3: inputs.pr_number is absent (the bug that prompted #806)
# The filter must work correctly even when the API returns inputs: null
# on the workflow_runs objects. This test verifies the fix: the filter no
# longer references .inputs at all, so null inputs do not block selection.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 3: inputs.pr_number absent (API returns null) ==="

# Test 3.1: Run with inputs: null is still selected (no inputs check needed)
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":500,"inputs":null}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "null_inputs_run_selected" "500" "$_id"
unset _json _result _id

# Test 3.2: Run without inputs field at all is still selected
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"in_progress","conclusion":null,"html_url":"https://a","id":501}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "missing_inputs_field_run_selected" "501" "$_id"
unset _json _result _id

# Test 3.3: Filter does NOT reference .inputs in the select clause
# This verifies structurally that the filter removed the inputs dependency.
if printf '%s\n' "$RUN_POLL_FILTER" | grep -q '\.inputs'; then
  _has_inputs=1
else
  _has_inputs=0
fi
run_test "filter_has_no_inputs_reference" "0" "$_has_inputs"
unset _has_inputs

# ---------------------------------------------------------------------------
# Area 4: in-progress run is not broken by the filter (status handling)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 4: in-progress run status passthrough ==="

# Test 4.1: in_progress run is returned (status field preserved)
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"in_progress","conclusion":null,"html_url":"https://a","id":600}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_status=$(printf '%s\n' "$_result" | jq -r '.status')
run_test "in_progress_status_returned" "in_progress" "$_status"
unset _json _result _status

# Test 4.2: queued run is returned (status field preserved)
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"queued","conclusion":null,"html_url":"https://a","id":700}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_status=$(printf '%s\n' "$_result" | jq -r '.status')
run_test "queued_status_returned" "queued" "$_status"
unset _json _result _status

# ---------------------------------------------------------------------------
# Area 5: Run-name PR scoping — concurrent dispatch correctness (#808)
#
# These are the critical behavioral tests for the fix: given a workflow_runs
# payload containing runs for TWO different PRs (same workflow-file and
# timestamp window), assert the filter selects the run whose name matches THIS
# PR — not merely the newest run regardless of PR.
#
# The scenario mirrors a parallel batch where PR #808 and PR #999 both dispatch
# claude-code-review.yml within the same poll window. Without the name filter,
# sort_by(.created_at) | reverse | first would select PR #999's run (newest).
# With the name filter, only PR #808's run matches.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 5: run-name PR scoping (concurrent dispatch) ==="

# Test 5.1: Two PRs dispatched; most-recent is other PR — filter selects THIS PR's run
# PR #808 run (id=810) was dispatched at 16:00; PR #999 run (id=999) dispatched at 16:01.
# Without name filter: id=999 would be selected (newest). With name filter: id=810 selected.
_json='{"workflow_runs":[
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #999","created_at":"2026-06-02T16:01:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":999},
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://b","id":810}
]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "concurrent_other_pr_newest_selects_this_pr" "810" "$_id"
unset _json _result _id

# Test 5.2: Only this PR's run is present — selected
_json='{"workflow_runs":[
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":820}
]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "only_this_pr_run_selected" "820" "$_id"
unset _json _result _id

# Test 5.3: Only the other PR's run is present — no match (id is null)
# When the poll window has only a run for PR #999 but not #808, the filter
# returns null (loop continues polling until THIS PR's run appears).
_json='{"workflow_runs":[
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #999","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":999}
]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id // "null"')
run_test "only_other_pr_run_returns_null" "null" "$_id"
unset _json _result _id

# Test 5.4: Filter requires run-name to contain the PR number token
# A run with name "Claude Code Review — PR #8080" must NOT match PR #808
# (word-boundary check: \b prevents "808" from matching "8080").
_json='{"workflow_runs":[
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #8080","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":8080}
]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id // "null"')
run_test "pr_number_word_boundary_no_false_match" "null" "$_id"
unset _json _result _id

# Test 5.4b: Dynamic PR input is compared as data, not interpolated as regex.
_json='{"workflow_runs":[
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #999","created_at":"2026-06-02T16:01:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":999},
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://b","id":808}
]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808|999")
_id=$(printf '%s\n' "$_result" | jq -r '.id // "null"')
run_test "pr_input_regex_metacharacters_are_literal" "null" "$_id"
unset _json _result _id

# Test 5.5: Two runs for THIS PR in the same window — most recent selected
# (regression guard: name filter must not break multi-run deduplication)
_json='{"workflow_runs":[
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:02:00Z","status":"completed","conclusion":"success","html_url":"https://b","id":830},
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":808}
]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "two_runs_same_pr_most_recent_selected" "830" "$_id"
unset _json _result _id

# Test 5.6: Runs can arrive out of timestamp order — newest created_at wins
# This fails without `sort_by(.created_at) | reverse | first` because the first
# input item is intentionally older than the later candidate for the same PR.
_json='{"workflow_runs":[
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":840},
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:03:00Z","status":"completed","conclusion":"success","html_url":"https://b","id":843},
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:01:00Z","status":"completed","conclusion":"success","html_url":"https://c","id":841}
]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "out_of_order_runs_newest_created_at_selected" "843" "$_id"
unset _json _result _id

# Test 5.7: Paginated workflow-run responses are flattened before selection
# The production poller uses `gh api --paginate` and slurps all page objects
# before applying the same filter. This guards against selecting only page 1.
_json='{"workflow_runs":[
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"failure","html_url":"https://page1","id":850}
]}
{"workflow_runs":[
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Review — PR #808","created_at":"2026-06-02T16:04:00Z","status":"completed","conclusion":"success","html_url":"https://page2","id":854}
]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "paginated_runs_flattened_newest_selected" "854" "$_id"
unset _json _result _id

# Test 5.8: Backward compat — old workflow (no run-name, generic names) falls back
# to timestamp-only selection. When no candidate has a "PR #N"-style name, the
# filter uses all candidates. The most recent one is selected regardless of name.
# This covers the transition period before the new workflow is deployed to main.
_json='{"workflow_runs":[
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Action PR Review","created_at":"2026-06-02T16:01:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":901},
  {"path":".github/workflows/claude-code-review.yml","name":"Claude Code Action PR Review","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://b","id":900}
]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z" "808")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "backward_compat_generic_name_falls_back_to_newest" "901" "$_id"
unset _json _result _id

# ---------------------------------------------------------------------------
# Area 6: epoch→ISO8601 conversion fallback
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 6: epoch→ISO8601 conversion fallback ==="

_date_mock_dir="$(mktemp -d)"
cat > "$_date_mock_dir/date" <<'MOCK_DATE'
#!/usr/bin/env bash
exit 1
MOCK_DATE
chmod +x "$_date_mock_dir/date"

_epoch_to_iso_with_python_fallback() {
  local epoch="$1"
  PATH="$_date_mock_dir:$PATH" date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    PATH="$_date_mock_dir:$PATH" date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    python3 -c "import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$epoch"
}

_iso="$(_epoch_to_iso_with_python_fallback 1700000000)"
run_test "python_fallback_epoch_to_iso" "2023-11-14T22:13:20Z" "$_iso"
rm -rf "$_date_mock_dir"
unset _date_mock_dir _iso

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
