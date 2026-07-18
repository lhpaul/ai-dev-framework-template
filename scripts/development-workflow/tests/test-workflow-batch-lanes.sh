#!/usr/bin/env bash
# test-workflow-batch-lanes.sh - Unit tests for stage lane assignment.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LANES="$REPO_ROOT/scripts/development-workflow/workflow-batch-lanes.sh"
BATCH_PLAN="$REPO_ROOT/scripts/development-workflow/workflow-batch-plan.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

write_batch_block() {
  local file="$1" slug="$2" next_action="$3" local_runtime="${4:-}" status="${5:-}" labels="${6:-}" skip_reason="${7:-}"
  {
    cat <<EOF
TARGET=development:docs/specs/developments/fake/$slug
DEVELOPMENT_PATH=docs/specs/developments/fake/$slug
SLUG=$slug
STATUS=$status
NEXT_ACTION=$next_action
BATCH_HINT=implementation
PARALLEL_SAFE=conditional
TOOL_FIX=no
EOF
    if [ -n "$local_runtime" ]; then
      echo "LOCAL_RUNTIME=$local_runtime"
    fi
    if [ -n "$labels" ]; then
      echo "LABELS=$labels"
    fi
    if [ -n "$skip_reason" ]; then
      echo "SKIP_REASON=$skip_reason"
    fi
    echo
  } >> "$file"
}

block_value() {
  local output="$1" slug="$2" field="$3"
  printf '%s\n' "$output" | awk -v slug="$slug" -v field="$field" '
    $0 == "SLUG=" slug { in_block=1 }
    in_block && $0 ~ "^" field "=" {
      sub("^" field "=", "")
      print
      exit
    }
    in_block && /^$/ { in_block=0 }
  '
}

fixture_repo="$TMP_ROOT/repo"
mkdir -p "$fixture_repo/docs/specs/developments"
cat > "$fixture_repo/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
guardrails:
  mode: manual
YAML

batch_file="$TMP_ROOT/mixed.batch"
: > "$batch_file"
write_batch_block "$batch_file" "item-spec" "run-spec-review-and-open-pr"
write_batch_block "$batch_file" "item-plan" "write-plan"
write_batch_block "$batch_file" "item-impl-a" "implement"
write_batch_block "$batch_file" "item-impl-b" "implement"

mixed_output="$("$LANES" --repo-root "$fixture_repo" < "$batch_file")"
run_test "spec_lane_proposed" "proposed" "$(block_value "$mixed_output" "item-spec" "DISPATCH")"
run_test "plan_lane_proposed" "proposed" "$(block_value "$mixed_output" "item-plan" "DISPATCH")"
run_test "first_impl_proposed" "proposed" "$(block_value "$mixed_output" "item-impl-a" "DISPATCH")"
run_test "second_impl_held" "held" "$(block_value "$mixed_output" "item-impl-b" "DISPATCH")"

category_file="$TMP_ROOT/categories.batch"
: > "$category_file"
write_batch_block "$category_file" "backlog-start" "write-spec" "" "Backlog"
write_batch_block "$category_file" "resume-plan" "write-plan" "" "Spec Ready"
write_batch_block "$category_file" "waiting-review" "wait-human-review" "" "Development in Review" "ready-for-human-review"
write_batch_block "$category_file" "held-impl-a" "implement" "" "Plan Ready"
write_batch_block "$category_file" "held-impl-b" "implement" "" "Plan Ready"
write_batch_block "$category_file" "skip-item-with-reason" "skip" "" "Done" "" "merged implementation branch already cleaned up"

category_output="$("$LANES" --repo-root "$fixture_repo" < "$category_file")"
run_test "backlog_start_category" "proposed_batch" "$(block_value "$category_output" "backlog-start" "REPORT_CATEGORY")"
run_test "backlog_start_label" "PROPOSED BATCH - your decision" "$(block_value "$category_output" "backlog-start" "REPORT_LABEL")"
run_test "resume_category" "actionable_resume" "$(block_value "$category_output" "resume-plan" "REPORT_CATEGORY")"
run_test "resume_label" "ACTIONABLE RESUME - can advance now" "$(block_value "$category_output" "resume-plan" "REPORT_LABEL")"
run_test "waiting_review_category" "informational" "$(block_value "$category_output" "waiting-review" "REPORT_CATEGORY")"
run_test "waiting_review_label" "INFORMATIONAL - not actionable in this proposal" "$(block_value "$category_output" "waiting-review" "REPORT_LABEL")"
run_test "waiting_review_reason" "Waiting on human review or merge outside the current run-work proposal." "$(block_value "$category_output" "waiting-review" "REPORT_REASON")"
run_test "held_category" "held" "$(block_value "$category_output" "held-impl-b" "REPORT_CATEGORY")"
run_test "held_label" "HELD - not included in proposed batch" "$(block_value "$category_output" "held-impl-b" "REPORT_LABEL")"
run_test "held_reason_reuses_hold_reason" "implementation lane cap (max 1)" "$(block_value "$category_output" "held-impl-b" "REPORT_REASON")"
run_test "skip_reason_reported" "merged implementation branch already cleaned up" "$(block_value "$category_output" "skip-item-with-reason" "REPORT_REASON")"

scan_no_paths_output="$("$LANES" --repo-root "$fixture_repo" --scan 2>&1)"
run_test "scan_mode_no_paths_returns_none" "yes" "$(printf '%s\n' "$scan_no_paths_output" | grep -q '^(none)$' && echo yes || echo no)"

high_parallel_repo="$TMP_ROOT/high-parallel"
mkdir -p "$high_parallel_repo/docs/specs/developments"
cat > "$high_parallel_repo/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
guardrails:
  mode: delegated
  parallelism:
    max_concurrent_by_stage:
      spec: 0
      plan: 0
      review: 0
      implementation: 3
YAML

exclusive_file="$TMP_ROOT/exclusive.batch"
: > "$exclusive_file"
write_batch_block "$exclusive_file" "impl-x" "implement" "exclusive"
write_batch_block "$exclusive_file" "impl-y" "implement" "none"

export WORKFLOW_MAX_CONCURRENT_IMPLEMENTATION=3
exclusive_output="$("$LANES" --repo-root "$high_parallel_repo" < "$exclusive_file")"
unset WORKFLOW_MAX_CONCURRENT_IMPLEMENTATION
run_test "exclusive_holds_second_impl" "held" "$(block_value "$exclusive_output" "impl-y" "DISPATCH")"
run_test "exclusive_hold_reason" "local runtime exclusivity (another implementation item requires exclusive local runtime)" "$(block_value "$exclusive_output" "impl-y" "HOLD_REASON")"

# classify_local_runtime via workflow-batch-plan on a synthetic plan folder
runtime_dev="$fixture_repo/docs/specs/developments/20260624120000_999-runtime-test"
mkdir -p "$runtime_dev"
cat > "$runtime_dev/2_999-runtime-test_implementation-plan.md" <<'MD'
# Implementation plan

## Files modified

```
src/app.ts
```

## Notes

Requires local dev server on localhost port 3000.
MD

export WORKFLOW_SKIP_FETCH=1
runtime_plan_out="$(cd "$fixture_repo" && "$BATCH_PLAN" "$runtime_dev" 2>/dev/null | awk '/^LOCAL_RUNTIME=/{print; exit}')"
run_test "local_runtime_exclusive_from_plan" "LOCAL_RUNTIME=exclusive" "$runtime_plan_out"

skip_file="$TMP_ROOT/skip.batch"
: > "$skip_file"
write_batch_block "$skip_file" "skip-item" "skip"
skip_output="$("$LANES" --repo-root "$fixture_repo" < "$skip_file")"
run_test "skip_action_not_proposed" "skip" "$(block_value "$skip_output" "skip-item" "DISPATCH")"

whitespace_output="$(printf ' \n\t\n\n' | "$LANES" --repo-root "$fixture_repo")"
run_test "whitespace_input_returns_none" "yes" "$(printf '%s\n' "$whitespace_output" | grep -q '^(none)$' && echo yes || echo no)"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
