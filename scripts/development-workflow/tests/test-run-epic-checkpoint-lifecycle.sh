#!/usr/bin/env bash
# test-run-epic-checkpoint-lifecycle.sh - Unit tests for checkpoint PR lifecycle.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir)"
case "$GIT_COMMON_DIR" in
  /*) REPO_ROOT="$(cd "$GIT_COMMON_DIR/.." && pwd -P)" ;;
  *) REPO_ROOT="$(cd "$SCRIPT_DIR/$GIT_COMMON_DIR/.." && pwd -P)" ;;
esac
HELPER="$REPO_ROOT/scripts/development-workflow/run-epic-checkpoint-lifecycle.sh"

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
printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"
case "$*" in
  auth\ status)
    exit 0
    ;;
  repo\ view\ --json\ nameWithOwner\ --jq\ .nameWithOwner)
    printf 'lhpaul/ai-dev-framework-template\n'
    ;;
  pr\ view\ 42\ --json\ labels\ --jq\ *)
    if [ "${MOCK_HAS_CHECKPOINT_LABEL:-0}" = "1" ]; then
      printf '1\n'
    else
      printf '0\n'
    fi
    ;;
  pr\ view\ 42\ --json\ reviews\ --jq\ *)
    if [ "${MOCK_REVIEW_APPROVED:-0}" = "1" ]; then
      cat <<'JSON'
[{"state":"APPROVED","author":{"login":"human-reviewer"},"submittedAt":"2026-06-22T12:00:00Z"}]
JSON
    else
      printf '[]\n'
    fi
    ;;
  pr\ edit\ 42\ --add-label\ human-checkpoint-required)
    printf 'added\n'
    ;;
  pr\ edit\ 42\ --remove-label\ human-checkpoint-required)
    printf 'removed\n'
    ;;
  api\ --paginate\ --slurp\ repos/lhpaul/ai-dev-framework-template/issues/42/comments\?per_page=100)
    if [ "${MOCK_COMMENT_MODE:-empty}" = "satisfied" ]; then
      cat <<'JSON'
[[{"user":{"login":"human-reviewer"},"body":"<!-- run-epic:checkpoint-satisfied:1022:plan:technical -->","created_at":"2026-06-22T12:00:00Z"}]]
JSON
    elif [ "${MOCK_COMMENT_MODE:-empty}" = "existing-marker" ]; then
      cat <<'JSON'
[[{"id":999,"user":{"login":"bot"},"body":"<!-- run-epic:checkpoint-status -->\nold"}]]
JSON
    else
      printf '[]\n'
    fi
    ;;
  api\ -X\ PATCH\ repos/lhpaul/ai-dev-framework-template/issues/comments/999\ --input\ -)
    printf '{"id":999}\n'
    ;;
  api\ -X\ POST\ repos/lhpaul/ai-dev-framework-template/issues/42/comments\ --input\ -)
    printf '{"id":1000}\n'
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

run_fails_contains() {
  local name="$1" expected="$2"
  shift 2
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ] && grep -Fq -- "$expected" <<< "$output"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected failure containing '${expected}'"
    printf 'Status: %s\nOutput:\n%s\n' "$status" "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

checkpoints_file="$TMP_ROOT/checkpoints.json"
cat > "$checkpoints_file" <<'JSON'
[
  {
    "item_number": 1022,
    "stage": "plan",
    "domain": "technical",
    "reason": "schema changes",
    "required_human_action": "approve data model",
    "satisfaction_state": "pending"
  },
  {
    "item_number": 9999,
    "stage": "plan",
    "domain": "technical",
    "reason": "other item",
    "required_human_action": "ignore",
    "satisfaction_state": "pending"
  }
]
JSON

echo ""
echo "=== Run epic checkpoint lifecycle ==="

run_fails_contains "requires_known_subcommand" "unknown or missing subcommand" "$HELPER"
run_test "stage_from_spec_branch" "spec" "$("$HELPER" stage-from-branch --branch spec/human-checkpoints)"
run_test "stage_from_plan_branch" "plan" "$("$HELPER" stage-from-branch --branch implementation-plan/human-checkpoints)"

blocking_output="$("$HELPER" evaluate-blocking --item 1022 --branch implementation-plan/human-checkpoints --checkpoints-file "$checkpoints_file")"
run_test "evaluate_blocking_plan_stage" "1" "$(printf '%s\n' "$blocking_output" | jq 'length')"
run_test "evaluate_blocking_same_item_only" "1022" "$(printf '%s\n' "$blocking_output" | jq -r '.[0].item_number')"

impl_blocking="$("$HELPER" evaluate-blocking --item 1022 --branch feature/human-checkpoints --checkpoints-file "$checkpoints_file")"
run_test "earlier_plan_checkpoint_blocks_implementation_pr" "1" "$(printf '%s\n' "$impl_blocking" | jq 'length')"

satisfied_file="$TMP_ROOT/satisfied-checkpoints.json"
MOCK_COMMENT_MODE=satisfied "$HELPER" detect-satisfaction --item 1022 --branch implementation-plan/human-checkpoints --checkpoints-file "$checkpoints_file" --pr 42 --write-checkpoints-file "$satisfied_file" >/dev/null
run_test "detect_satisfaction_via_comment" "satisfied" "$(jq -r '.[0].satisfaction_state' "$satisfied_file")"

no_block_after="$("$HELPER" evaluate-blocking --item 1022 --branch implementation-plan/human-checkpoints --checkpoints-file "$satisfied_file")"
run_test "satisfied_checkpoint_not_blocking" "0" "$(printf '%s\n' "$no_block_after" | jq 'length')"

comment_input="$TMP_ROOT/comment-input.json"
jq -n \
  --argjson item '{"number":1022}' \
  --argjson pr '{"number":42,"branch":"implementation-plan/human-checkpoints","stage":"plan"}' \
  --argjson checkpoints "$(cat "$checkpoints_file")" \
  --argjson blocking "$(printf '%s\n' "$blocking_output")" \
  '{
    item: $item,
    pr: $pr,
    checkpoints: $checkpoints,
    blocking: $blocking,
    label_required: true,
    satisfaction_signals: {
      comment_marker: "<!-- run-epic:checkpoint-satisfied:1022:plan:technical -->",
      waiver_marker: "<!-- run-epic:checkpoint-waived:1022:plan:technical --> rationale"
    }
  }' > "$comment_input"
comment_output="$("$HELPER" render-pr-checkpoint-comment --input "$comment_input")"
run_test "renders_checkpoint_marker" "yes" "$(grep -q '<!-- run-epic:checkpoint-status -->' <<< "$comment_output" && echo yes || echo no)"
run_test "renders_blocking_section" "yes" "$(grep -q 'approve data model' <<< "$comment_output" && echo yes || echo no)"

sync_output="$("$HELPER" sync-pr-labels --pr 42 --item 1022 --branch implementation-plan/human-checkpoints --checkpoints-file "$checkpoints_file")"
run_test "sync_applies_label_when_blocking" "LABEL_APPLIED=human-checkpoint-required" "$(grep '^LABEL_APPLIED=' <<< "$sync_output" || true)"
run_test "sync_reports_blocking_count" "BLOCKING_COUNT=1" "$(grep '^BLOCKING_COUNT=' <<< "$sync_output" || true)"

sync_remove_output="$(MOCK_HAS_CHECKPOINT_LABEL=1 MOCK_COMMENT_MODE=satisfied "$HELPER" sync-pr-labels --pr 42 --item 1022 --branch implementation-plan/human-checkpoints --checkpoints-file "$checkpoints_file")"
run_test "sync_removes_label_when_satisfied" "LABEL_REMOVED=human-checkpoint-required" "$(grep '^LABEL_REMOVED=' <<< "$sync_remove_output" || true)"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
