#!/usr/bin/env bash
# test-batch-merge-recheck-remaining.sh - Unit tests for post-merge PR rechecks.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HELPER="$REPO_ROOT/scripts/development-workflow/batch-merge.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/gh-calls.log"
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"

check_success='[{"__typename":"CheckRun","name":"policy","status":"COMPLETED","conclusion":"SUCCESS"}]'
check_pending='[{"__typename":"CheckRun","name":"policy","status":"IN_PROGRESS","conclusion":null}]'
check_failure='[{"__typename":"CheckRun","name":"policy","status":"COMPLETED","conclusion":"FAILURE"}]'

emit_pr() {
  pr="$1"
  state="$2"
  draft="$3"
  base="$4"
  head="$5"
  merge_state="$6"
  checks="$7"
  labels="${8:-ready}"
  if [ "$labels" = "ready" ]; then
    labels_json='[{"name":"ready-for-human-review"}]'
  else
    labels_json='[{"name":"needs-fixes"}]'
  fi
  printf '{"number":%s,"state":"%s","isDraft":%s,"baseRefName":"%s","headRefName":"%s","mergeStateStatus":"%s","labels":%s,"statusCheckRollup":%s}\n' \
    "$pr" "$state" "$draft" "$base" "$head" "$merge_state" "$labels_json" "$checks"
}

count_for() {
  key="$1"
  file="$MOCK_GH_STATE_DIR/$key.count"
  count=0
  [ -f "$file" ] && count="$(cat "$file")"
  count=$((count + 1))
  printf '%s\n' "$count" > "$file"
  printf '%s\n' "$count"
}

case "$*" in
  auth\ status)
    exit 0
    ;;
  pr\ list\ --base\ develop\ --state\ open\ --json\ number,headRefName,baseRefName,mergeStateStatus,statusCheckRollup)
    case "${MOCK_SCENARIO:-}" in
      dirty_out_of_scope|retry)
        printf '[{"number":104,"headRefName":"feature/out-of-scope-104","baseRefName":"develop","mergeStateStatus":"CLEAN","statusCheckRollup":%s}]\n' "$check_success"
        ;;
      observation_object)
        printf '{}\n'
        ;;
      observation_nested_object)
        printf '{"items":[]}\n'
        ;;
      *)
        printf '[]\n'
        ;;
    esac
    ;;
  pr\ view\ 102\ --json\ number,state,isDraft,labels,baseRefName,headRefName,mergeStateStatus,statusCheckRollup)
    case "${MOCK_SCENARIO:-}" in
      dirty_out_of_scope)
        emit_pr 102 OPEN false develop feature/mock-pr-102 DIRTY "$check_success"
        ;;
      retry)
        count="$(count_for pr102)"
        if [ "$count" -lt 3 ]; then
          emit_pr 102 OPEN false develop feature/mock-pr-102 CLEAN "$check_pending"
        else
          emit_pr 102 OPEN false develop feature/mock-pr-102 CLEAN "$check_success"
        fi
        ;;
      base_mismatch)
        emit_pr 102 OPEN false main feature/mock-pr-102 CLEAN "$check_success"
        ;;
      failing)
        emit_pr 102 OPEN false develop feature/mock-pr-102 CLEAN "$check_failure"
        ;;
      malformed_response)
        printf '{"number":102,"state":"OPEN","isDraft":false,"baseRefName":"develop","headRefName":"feature/mock-pr-102","mergeStateStatus":"CLEAN","statusCheckRollup":%s}\n' "$check_success"
        ;;
      dirty_pending)
        emit_pr 102 OPEN false develop feature/mock-pr-102 DIRTY "$check_pending"
        ;;
      previous_merged)
        emit_pr 102 MERGED false develop feature/mock-pr-102 CLEAN "$check_success"
        ;;
      *)
        emit_pr 102 OPEN false develop feature/mock-pr-102 CLEAN "$check_success"
        ;;
    esac
    ;;
  pr\ view\ 103\ --json\ number,state,isDraft,labels,baseRefName,headRefName,mergeStateStatus,statusCheckRollup)
    case "${MOCK_SCENARIO:-}" in
      dirty_out_of_scope)
        emit_pr 103 OPEN false develop feature/mock-pr-103 CLEAN "$check_success"
        ;;
      retry)
        emit_pr 103 OPEN false develop feature/mock-pr-103 UNKNOWN "$check_success"
        ;;
      deadline_after_retry)
        emit_pr 103 OPEN false develop feature/mock-pr-103 CLEAN "$check_pending"
        ;;
      previous_merged)
        emit_pr 103 OPEN false develop feature/mock-pr-103 CLEAN "$check_success"
        ;;
      *)
        emit_pr 103 OPEN false develop feature/mock-pr-103 BLOCKED "$check_success"
        ;;
    esac
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"
export MOCK_GH_CALL_LOG="$CALL_LOG"
export MOCK_GH_STATE_DIR="$TMP_ROOT/state"
mkdir -p "$MOCK_GH_STATE_DIR"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf 'FAIL: %s - expected %s, got %s\n' "$name" "$expected" "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

json_field() {
  local output="$1"
  local pr="$2"
  local field="$3"
  printf '%s\n' "$output" | jq -r --argjson pr "$pr" --arg field "$field" \
    'select(.pr == $pr) | .[$field] | if type == "boolean" then tostring else tostring end' | tail -n 1
}

schema_count() {
  local output="$1"
  printf '%s\n' "$output" | jq -s '
    map(select(
      has("record_type") and has("pr") and has("original_index") and
      has("invalidating_sibling_pr") and has("base_ref") and has("head_ref") and
      has("merge_state") and has("checks_state") and has("classification") and
      has("retryable") and has("attempts") and has("deadline_seconds") and
      has("outcome") and has("reason")
    )) | length'
}

echo ""
echo "=== Batch merge recheck remaining ==="

export MOCK_SCENARIO=dirty_out_of_scope
rm -f "$MOCK_GH_STATE_DIR"/*.count
dirty_output="$(BATCH_MERGE_RECHECK_SLEEP_SECONDS=0 "$HELPER" recheck-remaining --prs 101,102,103 --after-merged-pr 101 --base develop)"
run_test "dirty_pr_blocked" "merge_blocked" "$(json_field "$dirty_output" 102 classification)"
run_test "dirty_pr_names_sibling" "101" "$(json_field "$dirty_output" 102 invalidating_sibling_pr)"
run_test "clean_later_pr_continues" "continue" "$(json_field "$dirty_output" 103 outcome)"
run_test "out_of_scope_observed" "out_of_scope_observation" "$(json_field "$dirty_output" 104 record_type)"
run_test "out_of_scope_reason" "not_in_frozen_scope" "$(json_field "$dirty_output" 104 reason)"
run_test "schema_fields_present" "3" "$(schema_count "$dirty_output")"

export MOCK_SCENARIO=retry
rm -f "$MOCK_GH_STATE_DIR"/*.count
retry_output="$(BATCH_MERGE_RECHECK_ATTEMPTS=3 BATCH_MERGE_RECHECK_SLEEP_SECONDS=0 "$HELPER" recheck-remaining --prs 101,102,103 --after-merged-pr 101 --base develop)"
run_test "pending_becomes_clean" "clean" "$(json_field "$retry_output" 102 classification)"
run_test "pending_attempt_count" "3" "$(json_field "$retry_output" 102 attempts)"
run_test "unknown_attempts_exhausted" "retry_attempts_exhausted" "$(json_field "$retry_output" 103 reason)"
run_test "unknown_blocks" "merge_blocked" "$(json_field "$retry_output" 103 classification)"

rm -f "$MOCK_GH_STATE_DIR"/*.count
deadline_output="$(BATCH_MERGE_RECHECK_ATTEMPTS=99 BATCH_MERGE_RECHECK_SLEEP_SECONDS=1 BATCH_MERGE_RECHECK_DEADLINE_SECONDS=1 "$HELPER" recheck-remaining --prs 101,103 --after-merged-pr 101 --base develop)"
run_test "deadline_exhaustion_reason" "retry_deadline_exhausted" "$(json_field "$deadline_output" 103 reason)"

export MOCK_SCENARIO=deadline_after_retry
rm -f "$MOCK_GH_STATE_DIR"/*.count
deadline_after_retry_output="$(BATCH_MERGE_RECHECK_ATTEMPTS=99 BATCH_MERGE_RECHECK_SLEEP_SECONDS=1 BATCH_MERGE_RECHECK_DEADLINE_SECONDS=2 "$HELPER" recheck-remaining --prs 101,103 --after-merged-pr 101 --base develop)"
run_test "deadline_after_retry_emits_record" "merge_blocked" "$(json_field "$deadline_after_retry_output" 103 classification)"
run_test "deadline_after_retry_reason" "retry_deadline_exhausted" "$(json_field "$deadline_after_retry_output" 103 reason)"

export MOCK_SCENARIO=base_mismatch
rm -f "$MOCK_GH_STATE_DIR"/*.count
base_output="$("$HELPER" recheck-remaining --prs 101,102 --after-merged-pr 101 --base develop)"
run_test "base_mismatch_blocks" "base_ref_mismatch" "$(json_field "$base_output" 102 reason)"

export MOCK_SCENARIO=previous_merged
rm -f "$MOCK_GH_STATE_DIR"/*.count
previous_merged_output="$("$HELPER" recheck-remaining --prs 101,102,103 --after-merged-pr 101 --base develop)"
run_test "previously_merged_sibling_omitted" "0" "$(printf '%s\n' "$previous_merged_output" | jq -s '[.[] | select(.pr == 102)] | length')"
run_test "later_pr_still_checked_after_prior_merge" "clean" "$(json_field "$previous_merged_output" 103 classification)"

export MOCK_SCENARIO=failing
rm -f "$MOCK_GH_STATE_DIR"/*.count
failing_output="$("$HELPER" recheck-remaining --prs 101,102 --after-merged-pr 101 --base develop)"
run_test "failing_checks_block" "checks_failed" "$(json_field "$failing_output" 102 reason)"

export MOCK_SCENARIO=dirty_pending
rm -f "$MOCK_GH_STATE_DIR"/*.count
dirty_pending_output="$("$HELPER" recheck-remaining --prs 101,102 --after-merged-pr 101 --base develop)"
run_test "dirty_state_overrides_pending_checks" "merge_state_non_clean" "$(json_field "$dirty_pending_output" 102 reason)"
run_test "dirty_pending_not_retryable" "false" "$(json_field "$dirty_pending_output" 102 retryable)"

export MOCK_SCENARIO=malformed_response
set +e
malformed_output="$("$HELPER" recheck-remaining --prs 101,102 --after-merged-pr 101 --base develop)"
malformed_status=$?
set -e
run_test "malformed_response_status" "2" "$malformed_status"
run_test "malformed_response_classification" "helper_failed" "$(json_field "$malformed_output" 102 classification)"
run_test "malformed_response_reason" "missing_required_field" "$(json_field "$malformed_output" 102 reason)"

export MOCK_SCENARIO=observation_object
set +e
observation_object_output="$("$HELPER" recheck-remaining --prs 101,102 --after-merged-pr 101 --base develop)"
observation_object_status=$?
set -e
run_test "observation_object_status" "2" "$observation_object_status"
run_test "observation_object_reason" "malformed_response" "$(json_field "$observation_object_output" null reason)"

export MOCK_SCENARIO=observation_nested_object
set +e
observation_nested_output="$("$HELPER" recheck-remaining --prs 101,102 --after-merged-pr 101 --base develop)"
observation_nested_status=$?
set -e
run_test "observation_nested_object_status" "2" "$observation_nested_status"
run_test "observation_nested_object_reason" "malformed_response" "$(json_field "$observation_nested_output" null reason)"

set +e
bad_config_output="$(BATCH_MERGE_RECHECK_ATTEMPTS=0 "$HELPER" recheck-remaining --prs 101,102 --after-merged-pr 101 --base develop)"
bad_config_status=$?
set -e
run_test "invalid_config_status" "2" "$bad_config_status"
run_test "invalid_config_error_record" "helper_failed" "$(json_field "$bad_config_output" null classification)"

run_test "no_mutation_calls" "0" "$(grep -Ec 'pr edit|pr merge|pr comment' "$CALL_LOG" || true)"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
