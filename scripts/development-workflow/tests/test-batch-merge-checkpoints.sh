#!/usr/bin/env bash
# test-batch-merge-checkpoints.sh - Unit tests for batch merge checkpoint guards.

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
printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"
case "$*" in
  auth\ status)
    exit 0
    ;;
  pr\ list\ --base\ develop\ --label\ ready-for-human-review\ --state\ open\ --json\ number\ --jq\ .[].number)
    printf '42\n43\n'
    ;;
  pr\ view\ 42\ --json\ number,title,headRefName,baseRefName,labels,createdAt,isDraft)
    cat <<'JSON'
{"number":42,"title":"checkpointed PR","headRefName":"feature/42-checkpointed","baseRefName":"develop","labels":[{"name":"ready-for-human-review"},{"name":"ready-for-regression"},{"name":"human-checkpoint-required"}],"createdAt":"2026-06-22T12:00:00Z","isDraft":false}
JSON
    ;;
  pr\ view\ 43\ --json\ number,title,headRefName,baseRefName,labels,createdAt,isDraft)
    cat <<'JSON'
{"number":43,"title":"clean PR","headRefName":"feature/43-clean","baseRefName":"develop","labels":[{"name":"ready-for-human-review"},{"name":"ready-for-regression"}],"createdAt":"2026-06-22T12:01:00Z","isDraft":false}
JSON
    ;;
  pr\ view\ 44\ --json\ number,title,headRefName,baseRefName,labels,createdAt,isDraft)
    printf 'metadata unavailable for PR 44\n' >&2
    exit 70
    ;;
  pr\ view\ 42\ --json\ headRefName,baseRefName,state,labels,isDraft)
    cat <<'JSON'
{"headRefName":"feature/42-checkpointed","baseRefName":"develop","state":"OPEN","labels":[{"name":"ready-for-human-review"},{"name":"ready-for-regression"},{"name":"human-checkpoint-required"}],"isDraft":false}
JSON
    ;;
  pr\ view\ 45\ --json\ headRefName,baseRefName,state,labels,isDraft)
    cat <<'JSON'
{"headRefName":"feature/45-paused","baseRefName":"develop","state":"OPEN","labels":[{"name":"ready-for-human-review"},{"name":"ready-for-regression"},{"name":"do-not-merge"}],"isDraft":false}
JSON
    ;;
  pr\ diff\ 42\ --name-only|pr\ diff\ 43\ --name-only)
    printf 'scripts/example.sh\n'
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

echo ""
echo "=== Batch merge checkpoint guards ==="

discover_stderr="$TMP_ROOT/discover.err"
discover_output="$("$HELPER" discover 2>"$discover_stderr")"
run_test "discovery_warns_about_checkpoint" "yes" "$(grep -q 'human-checkpoint-required' "$discover_stderr" && echo yes || echo no)"
run_test "discovery_skips_checkpointed_pr" "no" "$(grep -q '^PR_NUMBER=42$' <<< "$discover_output" && echo yes || echo no)"
run_test "discovery_keeps_clean_pr" "yes" "$(grep -q '^PR_NUMBER=43$' <<< "$discover_output" && echo yes || echo no)"

include_output="$("$HELPER" discover --include-checkpointed --prs 42)"
run_test "explicit_checkpoint_include_emits_candidate" "yes" "$(grep -q '^PR_NUMBER=42$' <<< "$include_output" && echo yes || echo no)"
run_test "explicit_checkpoint_candidate_marks_flag" "true" "$(awk -F= '$1=="PR_HAS_HUMAN_CHECKPOINT"{print $2; exit}' <<< "$include_output")"

set +e
explicit_missing_output="$("$HELPER" discover --prs 44 2>&1)"
explicit_missing_status=$?
set -e
run_test "explicit_discovery_metadata_failure_exit" "2" "$explicit_missing_status"
run_test "explicit_discovery_metadata_failure_message" "yes" "$(grep -q 'explicitly requested PR #44' <<< "$explicit_missing_output" && echo yes || echo no)"

set +e
merge_output="$("$HELPER" merge --pr 42 2>&1)"
merge_status=$?
set -e
run_test "merge_refuses_checkpoint_label_status" "2" "$merge_status"
run_test "merge_refuses_checkpoint_label_message" "yes" "$(grep -q 'human-checkpoint-required' <<< "$merge_output" && echo yes || echo no)"

set +e
do_not_merge_output="$("$HELPER" merge --pr 45 2>&1)"
do_not_merge_status=$?
set -e
run_test "merge_refuses_do_not_merge_label_status" "2" "$do_not_merge_status"
run_test "merge_refuses_do_not_merge_label_message" "yes" "$(grep -q 'do-not-merge' <<< "$do_not_merge_output" && echo yes || echo no)"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
