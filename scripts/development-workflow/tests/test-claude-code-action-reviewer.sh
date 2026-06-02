#!/usr/bin/env bash
# test-claude-code-action-reviewer.sh — Unit tests for the run-poll jq filter
# logic in claude-code-action-reviewer.sh.
#
# Tests verify that the timestamp-only filter (post-#806 fix) selects the
# correct run from the GitHub Actions Runs API response and does NOT rely on
# inputs.pr_number (which is always null in the API).
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
# Arguments: $wf (workflow filename suffix), $poll_after (ISO8601 timestamp)
# ---------------------------------------------------------------------------
RUN_POLL_FILTER='[.workflow_runs[] | select((.path | endswith($wf)) and .created_at >= $poll_after)] | sort_by(.created_at) | reverse | first | {status: .status, conclusion: .conclusion, html_url: .html_url, id: .id}'

run_filter() {
  local json="$1" wf="$2" poll_after="$3"
  printf '%s\n' "$json" | jq -r \
    --arg wf "$wf" \
    --arg poll_after "$poll_after" \
    "$RUN_POLL_FILTER"
}

# ---------------------------------------------------------------------------
# Area 1: Basic timestamp filtering
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 1: timestamp filtering ==="

# Test 1.1: A single matching run is selected
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://github.com/owner/repo/actions/runs/100","id":100}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "single_match_selected" "100" "$_id"
unset _json _result _id

# Test 1.2: A run before poll_after is excluded — filter returns object with null id
# When the filtered array is empty, jq `first` on [] returns null; piping through
# `| {id: .id}` yields {"id":null}. The script treats this as "no match found"
# via the `RUN_STATUS=$(... '.status // empty')` guard (empty string → loop continues).
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","created_at":"2026-06-02T15:58:00Z","status":"completed","conclusion":"success","html_url":"https://github.com/owner/repo/actions/runs/99","id":99}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z")
_id=$(printf '%s\n' "$_result" | jq -r '.id // "null"')
run_test "old_run_excluded_null_id" "null" "$_id"
unset _json _result _id

# Test 1.3: Multiple runs — most recent is selected
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","created_at":"2026-06-02T16:01:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":200},{"path":".github/workflows/claude-code-review.yml","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://b","id":100}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "most_recent_selected" "200" "$_id"
unset _json _result _id

# Test 1.4: Empty workflow_runs → no match (id field is null)
_json='{"workflow_runs":[]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z")
_id=$(printf '%s\n' "$_result" | jq -r '.id // "null"')
run_test "empty_list_null_id" "null" "$_id"
unset _json _result _id

# ---------------------------------------------------------------------------
# Area 2: Workflow file path matching
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2: workflow file path matching ==="

# Test 2.1: A run with a different workflow file is excluded (id field is null)
_json='{"workflow_runs":[{"path":".github/workflows/other-workflow.yml","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":300}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z")
_id=$(printf '%s\n' "$_result" | jq -r '.id // "null"')
run_test "different_workflow_excluded_null_id" "null" "$_id"
unset _json _result _id

# Test 2.2: Mixed runs — only the matching workflow file is selected
_json='{"workflow_runs":[{"path":".github/workflows/other-workflow.yml","created_at":"2026-06-02T16:01:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":400},{"path":".github/workflows/claude-code-review.yml","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://b","id":401}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z")
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

# Test 3.1: Run with inputs: null is still selected (no inputs check)
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","created_at":"2026-06-02T16:00:00Z","status":"completed","conclusion":"success","html_url":"https://a","id":500,"inputs":null}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "null_inputs_run_selected" "500" "$_id"
unset _json _result _id

# Test 3.2: Run without inputs field at all is still selected
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","created_at":"2026-06-02T16:00:00Z","status":"in_progress","conclusion":null,"html_url":"https://a","id":501}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z")
_id=$(printf '%s\n' "$_result" | jq -r '.id')
run_test "missing_inputs_field_run_selected" "501" "$_id"
unset _json _result _id

# Test 3.3: Filter does NOT reference .inputs in the select clause
# This verifies structurally that the filter removed the inputs dependency.
if printf '%s\n' "$RUN_POLL_FILTER" | grep -q 'inputs'; then
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
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","created_at":"2026-06-02T16:00:00Z","status":"in_progress","conclusion":null,"html_url":"https://a","id":600}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z")
_status=$(printf '%s\n' "$_result" | jq -r '.status')
run_test "in_progress_status_returned" "in_progress" "$_status"
unset _json _result _status

# Test 4.2: queued run is returned (status field preserved)
_json='{"workflow_runs":[{"path":".github/workflows/claude-code-review.yml","created_at":"2026-06-02T16:00:00Z","status":"queued","conclusion":null,"html_url":"https://a","id":700}]}'
_result=$(run_filter "$_json" "claude-code-review.yml" "2026-06-02T15:59:00Z")
_status=$(printf '%s\n' "$_result" | jq -r '.status')
run_test "queued_status_returned" "queued" "$_status"
unset _json _result _status

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
