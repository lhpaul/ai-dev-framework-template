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
  local file="$1" slug="$2" next_action="$3" local_runtime="${4:-}"
  {
    cat <<EOF
TARGET=development:docs/specs/developments/fake/$slug
DEVELOPMENT_PATH=docs/specs/developments/fake/$slug
SLUG=$slug
NEXT_ACTION=$next_action
BATCH_HINT=implementation
PARALLEL_SAFE=conditional
TOOL_FIX=no
EOF
    if [ -n "$local_runtime" ]; then
      echo "LOCAL_RUNTIME=$local_runtime"
    fi
    echo
  } >> "$file"
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
run_test "spec_lane_proposed" "proposed" "$(printf '%s\n' "$mixed_output" | awk '/SLUG=item-spec/{f=1} f&&/^DISPATCH=/{sub(/^DISPATCH=/,""); print; exit}')"
run_test "plan_lane_proposed" "proposed" "$(printf '%s\n' "$mixed_output" | awk '/SLUG=item-plan/{f=1} f&&/^DISPATCH=/{sub(/^DISPATCH=/,""); print; exit}')"
run_test "first_impl_proposed" "proposed" "$(printf '%s\n' "$mixed_output" | awk '/SLUG=item-impl-a/{f=1} f&&/^DISPATCH=/{sub(/^DISPATCH=/,""); print; exit}')"
run_test "second_impl_held" "held" "$(printf '%s\n' "$mixed_output" | awk '/SLUG=item-impl-b/{f=1} f&&/^DISPATCH=/{sub(/^DISPATCH=/,""); print; exit}')"

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
run_test "exclusive_holds_second_impl" "held" "$(printf '%s\n' "$exclusive_output" | awk '/SLUG=impl-y/{f=1} f&&/^DISPATCH=/{sub(/^DISPATCH=/,""); print; exit}')"
run_test "exclusive_hold_reason" "local runtime exclusivity (another implementation item requires exclusive local runtime)" "$(printf '%s\n' "$exclusive_output" | awk '/SLUG=impl-y/{f=1} f&&/^HOLD_REASON=/{sub(/^HOLD_REASON=/,""); print; exit}')"

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
run_test "skip_action_not_proposed" "skip" "$(printf '%s\n' "$skip_output" | awk '/SLUG=skip-item/{f=1} f&&/^DISPATCH=/{sub(/^DISPATCH=/,""); print; exit}')"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
