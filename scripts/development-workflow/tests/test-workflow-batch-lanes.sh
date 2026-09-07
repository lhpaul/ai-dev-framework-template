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
issue_tracker:
  provider: none
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

review_cap_file="$TMP_ROOT/review-cap.batch"
: > "$review_cap_file"
write_batch_block "$review_cap_file" "waiting-review-a" "wait-human-review" "" "Development in Review" "ready-for-human-review"
write_batch_block "$review_cap_file" "waiting-review-b" "wait-human-review" "" "Development in Review" "ready-for-human-review"
review_cap_output="$(WORKFLOW_MAX_CONCURRENT_REVIEW=1 "$LANES" --repo-root "$fixture_repo" < "$review_cap_file")"
run_test "held_waiting_review_stays_informational" "informational" "$(block_value "$review_cap_output" "waiting-review-b" "REPORT_CATEGORY")"
run_test "held_waiting_review_uses_wait_reason" "Waiting on human review or merge outside the current run-work proposal." "$(block_value "$review_cap_output" "waiting-review-b" "REPORT_REASON")"

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

overlap_batch="$TMP_ROOT/overlap.batch"
: > "$overlap_batch"
write_batch_block "$overlap_batch" "overlap-a" "implement" "" "Plan Ready"
write_batch_block "$overlap_batch" "overlap-b" "implement" "" "Plan Ready"
overlap_input="$TMP_ROOT/overlap-input.json"
jq -n '{
  items: [
    {
      id: "overlap-a",
      title: "Users endpoint",
      brief: "Update GET /api/users.",
      fileSet: "unknown",
      priority: "High",
      createdAt: "2026-01-01T00:00:00Z",
      nextAction: "implement"
    },
    {
      id: "overlap-b",
      title: "User details",
      brief: "Update GET /api/users/:id.",
      fileSet: "unknown",
      priority: "Normal",
      createdAt: "2026-01-02T00:00:00Z",
      nextAction: "implement"
    }
  ]
}' > "$overlap_input"
export WORKFLOW_MAX_CONCURRENT_IMPLEMENTATION=3
overlap_output="$("$LANES" --repo-root "$high_parallel_repo" --overlap-input "$overlap_input" < "$overlap_batch")"
unset WORKFLOW_MAX_CONCURRENT_IMPLEMENTATION
run_test "overlap_keep_item_proposed" "proposed" "$(block_value "$overlap_output" "overlap-a" "DISPATCH")"
run_test "overlap_held_item_serialized" "held" "$(block_value "$overlap_output" "overlap-b" "DISPATCH")"
run_test "overlap_hold_reason" "planless overlap serialization (overlap-a--overlap-b); held until prior item merges into approved base" "$(block_value "$overlap_output" "overlap-b" "HOLD_REASON")"
run_test "overlap_group_visible" "overlap-a--overlap-b" "$(block_value "$overlap_output" "overlap-b" "OVERLAP_SERIAL_GROUP")"

numeric_overlap_batch="$TMP_ROOT/numeric-overlap.batch"
: > "$numeric_overlap_batch"
write_batch_block "$numeric_overlap_batch" "1001-overlap-a" "implement" "" "Plan Ready"
write_batch_block "$numeric_overlap_batch" "1002-overlap-b" "implement" "" "Plan Ready"
numeric_overlap_input="$TMP_ROOT/numeric-overlap-input.json"
jq -n '{
  items: [
    {
      id: "1001",
      title: "Users endpoint",
      brief: "Update GET /api/users.",
      fileSet: "unknown",
      priority: "High",
      createdAt: "2026-01-01T00:00:00Z",
      nextAction: "implement"
    },
    {
      id: "1002",
      title: "User details",
      brief: "Update GET /api/users/:id.",
      fileSet: "unknown",
      priority: "Normal",
      createdAt: "2026-01-02T00:00:00Z",
      nextAction: "implement"
    }
  ]
}' > "$numeric_overlap_input"
export WORKFLOW_MAX_CONCURRENT_IMPLEMENTATION=3
numeric_overlap_output="$("$LANES" --repo-root "$high_parallel_repo" --overlap-input "$numeric_overlap_input" < "$numeric_overlap_batch")"
unset WORKFLOW_MAX_CONCURRENT_IMPLEMENTATION
run_test "overlap_numeric_issue_alias_holds_slug" "held" "$(block_value "$numeric_overlap_output" "1002-overlap-b" "DISPATCH")"
run_test "overlap_numeric_group_visible_on_slug" "1001--1002" "$(block_value "$numeric_overlap_output" "1002-overlap-b" "OVERLAP_SERIAL_GROUP")"

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
runtime_plan_out="$(cd "$fixture_repo" && AI_DEV_WORKFLOW_CONFIG_FILE="$fixture_repo/.ai-dev-workflow.yaml" "$BATCH_PLAN" "$runtime_dev" 2>/dev/null | awk '/^LOCAL_RUNTIME=/{print; exit}')"
run_test "local_runtime_exclusive_from_plan" "LOCAL_RUNTIME=exclusive" "$runtime_plan_out"

git -C "$fixture_repo" init -q
git -C "$fixture_repo" config user.email test@example.com
git -C "$fixture_repo" config user.name "Test User"
git -C "$fixture_repo" commit --allow-empty -m "initial fixture" >/dev/null
git -C "$fixture_repo" update-ref refs/remotes/origin/feature/999-ready-pr HEAD

ready_pr_dev="$fixture_repo/docs/specs/developments/20260624121000_999-ready-pr"
mkdir -p "$ready_pr_dev"
cat > "$ready_pr_dev/1_999-ready-pr_specs.md" <<'MD'
# Spec
MD
cat > "$ready_pr_dev/2_999-ready-pr_implementation-plan.md" <<'MD'
# Implementation plan
MD

mock_bin="$TMP_ROOT/mock-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
  exit 0
fi
if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ]; then
  case "$*" in
    *nameWithOwner*) printf 'test-owner/test-repo\n' ;;
    *owner*) printf 'test-owner\n' ;;
    *name*) printf 'test-repo\n' ;;
    *) printf 'test-owner/test-repo\n' ;;
  esac
  exit 0
fi
if [ "${1:-}" = "api" ] && [ "${2:-}" = "graphql" ]; then
  case "$*" in
    *"projectV2(number"*)
      printf '{"data":{"user":{"projectV2":{"id":"PVT_test"}}}}\n'
      ;;
    *"repository(owner"*)
      printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_test","project":{"id":"PVT_test","number":1},"status":{"name":"In Development"},"configuredType":{"name":"Workflow"},"customType":null,"compactCustomType":null,"type":{"name":"Workflow"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}\n'
      ;;
    *)
      printf 'unexpected gh graphql call: %s\n' "$*" >&2
      exit 1
      ;;
  esac
  exit 0
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  if [ "${MOCK_GH_PR_LIST_FAIL:-0}" = "1" ]; then
    printf 'mock pr list failure\n' >&2
    exit 1
  fi
  printf '[{"number":42,"headRefName":"feature/999-ready-pr","labels":[{"name":"ready-for-human-review"}]}]\n'
  exit 0
fi
printf 'unexpected gh call: %s\n' "$*" >&2
exit 1
SH
chmod +x "$mock_bin/gh"

ready_pr_plan_out="$(PATH="$mock_bin:$PATH" WORKFLOW_SKIP_FETCH=1 AI_DEV_WORKFLOW_CONFIG_FILE="$fixture_repo/.ai-dev-workflow.yaml" "$BATCH_PLAN" --repo-root "$fixture_repo" "$ready_pr_dev")"
run_test "batch_plan_emits_pr_labels" "PR_LABELS=ready-for-human-review" "$(printf '%s\n' "$ready_pr_plan_out" | awk '/^PR_LABELS=/{print; exit}')"
ready_pr_lane_out="$(printf '%s\n' "$ready_pr_plan_out" | "$LANES" --repo-root "$fixture_repo")"
run_test "ready_pr_metadata_is_informational" "informational" "$(block_value "$ready_pr_lane_out" "999-ready-pr" "REPORT_CATEGORY")"

unavailable_pr_plan_out="$(PATH="$mock_bin:$PATH" MOCK_GH_PR_LIST_FAIL=1 WORKFLOW_SKIP_FETCH=1 AI_DEV_WORKFLOW_CONFIG_FILE="$fixture_repo/.ai-dev-workflow.yaml" "$BATCH_PLAN" --repo-root "$fixture_repo" "$ready_pr_dev")"
run_test "batch_plan_emits_pr_metadata_unavailable" "PR_METADATA_STATUS=unavailable" "$(printf '%s\n' "$unavailable_pr_plan_out" | awk '/^PR_METADATA_STATUS=/{print; exit}')"
unavailable_pr_lane_out="$(printf '%s\n' "$unavailable_pr_plan_out" | "$LANES" --repo-root "$fixture_repo")"
run_test "unavailable_pr_metadata_is_informational" "informational" "$(block_value "$unavailable_pr_lane_out" "999-ready-pr" "REPORT_CATEGORY")"
run_test "unavailable_pr_metadata_reason" "Open PR metadata unavailable (gh_pr_list_failed); not actionable in this proposal." "$(block_value "$unavailable_pr_lane_out" "999-ready-pr" "REPORT_REASON")"

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
