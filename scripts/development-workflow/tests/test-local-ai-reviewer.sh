#!/usr/bin/env bash
# Unit tests for local-ai-reviewer.sh.
# covers: scripts/development-workflow/local-ai-reviewer.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
REVIEWER="$REPO_ROOT/scripts/development-workflow/local-ai-reviewer.sh"

MOCK_BIN="$(mktemp -d)"
NO_GRAPH_BIN="$(mktemp -d)"
OUTPUT_FILE="$(mktemp)"
STDERR_FILE="$(mktemp)"
EXIT_FILE="$(mktemp)"
VALID_REPO_ROOT="$(mktemp -d)"

cleanup() {
  local status=$?
  rm -rf "$MOCK_BIN" "$NO_GRAPH_BIN" "$VALID_REPO_ROOT"
  rm -f "$OUTPUT_FILE" "$STDERR_FILE" "$EXIT_FILE"
  exit "$status"
}
trap cleanup EXIT

for _cmd in awk bash cat dirname git grep jq mktemp rm sh sleep tr; do
  _cmd_path="$(command -v "$_cmd")"
  ln -sf "$_cmd_path" "$NO_GRAPH_BIN/$_cmd"
done
unset _cmd _cmd_path

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

install_gh_mock() {
  cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view 123"*"--json baseRefName,headRefName,headRefOid"*)
    if [ -n "${MOCK_PR_HEAD_SHA:-}" ]; then
      mock_head_sha="$MOCK_PR_HEAD_SHA"
    elif ! mock_head_sha="$(git rev-parse HEAD 2>/dev/null)"; then
      mock_head_sha=""
    fi
    printf '{"baseRefName":"develop","headRefName":"feature/test","headRefOid":"%s"}\n' "$mock_head_sha"
    exit 0
    ;;
  *"pr diff 123"*"--name-only"*)
    printf 'scripts/example.sh\nREVIEW.md\n'
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
MOCK_GH
  chmod +x "$MOCK_BIN/gh"
}

install_local_reviewer_mock() {
  cat > "$MOCK_BIN/local-reviewer-mock" <<'MOCK_REVIEWER'
#!/usr/bin/env bash
if [ -n "${MOCK_LOCAL_REVIEWER_SLEEP:-}" ]; then
  sleep "$MOCK_LOCAL_REVIEWER_SLEEP"
fi
if [ -n "${MOCK_LOCAL_REVIEWER_STDERR:-}" ]; then
  printf '%s\n' "$MOCK_LOCAL_REVIEWER_STDERR" >&2
fi
if [ -n "${MOCK_LOCAL_REVIEWER_STDOUT:-}" ]; then
  printf '%s\n' "$MOCK_LOCAL_REVIEWER_STDOUT"
fi
exit "${MOCK_LOCAL_REVIEWER_EXIT:-0}"
MOCK_REVIEWER
  chmod +x "$MOCK_BIN/local-reviewer-mock"
}

reset_mocks() {
  rm -f "$MOCK_BIN/gh" "$MOCK_BIN/local-reviewer-mock"
  install_gh_mock
  install_local_reviewer_mock
  unset MOCK_PR_HEAD_SHA MOCK_LOCAL_REVIEWER_STDOUT MOCK_LOCAL_REVIEWER_STDERR
  unset MOCK_LOCAL_REVIEWER_EXIT MOCK_LOCAL_REVIEWER_SLEEP
  unset LOCAL_AI_REVIEWER_COMMAND LOCAL_AI_REVIEWER_DISABLED LOCAL_AI_REVIEWER_TIMEOUT
  unset LOCAL_AI_REVIEWER_GRAPH_STRATEGY
}

set_mock_stdout() {
  MOCK_LOCAL_REVIEWER_STDOUT="$1"
}

init_repo_root_fixture() {
  git -C "$VALID_REPO_ROOT" init -q
  git -C "$VALID_REPO_ROOT" config user.email "test@example.com"
  git -C "$VALID_REPO_ROOT" config user.name "Test User"
  printf '# Review\n' > "$VALID_REPO_ROOT/REVIEW.md"
  git -C "$VALID_REPO_ROOT" add REVIEW.md
  git -C "$VALID_REPO_ROOT" commit -q -m "fixture"
  git -C "$VALID_REPO_ROOT" remote add origin "git@github.com:owner/repo.git"
}

run_reviewer() {
  local path_value="$1"
  shift
  set +e
  PATH="$path_value" "$REVIEWER" 123 owner repo "$@" >"$OUTPUT_FILE" 2>"$STDERR_FILE"
  local status=$?
  set -e
  printf '%s\n' "$status" > "$EXIT_FILE"
}

line_for() {
  local key="$1"
  grep "^${key}=" "$OUTPUT_FILE" | head -n 1 || true
}

exit_code() {
  cat "$EXIT_FILE"
}

init_repo_root_fixture

reset_mocks
LOCAL_AI_REVIEWER_DISABLED=1
export LOCAL_AI_REVIEWER_DISABLED
run_reviewer "$MOCK_BIN:$PATH"
run_test "disabled_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "disabled_reason" "REASON=disabled_by_config" "$(line_for REASON)"
run_test "disabled_exit" "3" "$(exit_code)"

reset_mocks
run_reviewer "$MOCK_BIN:$PATH"
run_test "missing_command_result" "RESULT=escalate" "$(line_for RESULT)"
run_test "missing_command_reason" "REASON=missing_command" "$(line_for REASON)"
run_test "missing_command_exit" "2" "$(exit_code)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
set_mock_stdout '{"result":"clean","findings":[]}'
export LOCAL_AI_REVIEWER_COMMAND MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH"
run_test "clean_result" "RESULT=clean" "$(line_for RESULT)"
run_test "clean_comments" "COMMENT_COUNT=0" "$(line_for COMMENT_COUNT)"
run_test "clean_exit" "0" "$(exit_code)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
set_mock_stdout '{"findings":[{"severity":"low","advisory":true,"message":"optional wording"}]}'
export LOCAL_AI_REVIEWER_COMMAND MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH"
run_test "advisory_result" "RESULT=clean" "$(line_for RESULT)"
run_test "advisory_suggestions" "SUGGESTION_COUNT=1" "$(line_for SUGGESTION_COUNT)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
set_mock_stdout '{"findings":[{"severity":"suggestion","clear_in_scope":true,"message":"add missing test"}]}'
export LOCAL_AI_REVIEWER_COMMAND MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH"
run_test "clear_in_scope_suggestion_result" "RESULT=needs_fixes" "$(line_for RESULT)"
run_test "clear_in_scope_suggestion_blocking" "BLOCKING_COUNT=1" "$(line_for BLOCKING_COUNT)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
set_mock_stdout '{"findings":[{"severity":"important","message":"fix before ready"}]}'
export LOCAL_AI_REVIEWER_COMMAND MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH"
run_test "important_result" "RESULT=needs_fixes" "$(line_for RESULT)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
set_mock_stdout '{"result":"clean","findings":[{"severity":"important","message":"fix before ready"}]}'
export LOCAL_AI_REVIEWER_COMMAND MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH"
run_test "explicit_clean_with_important_result" "RESULT=needs_fixes" "$(line_for RESULT)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
set_mock_stdout '{"result":"needs_rerun","reason":"state_changed","findings":[]}'
export LOCAL_AI_REVIEWER_COMMAND MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH"
run_test "needs_rerun_result" "RESULT=needs_rerun" "$(line_for RESULT)"
run_test "needs_rerun_reason" "REASON=state_changed" "$(line_for REASON)"
run_test "needs_rerun_exit" "1" "$(exit_code)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
set_mock_stdout 'not json'
export LOCAL_AI_REVIEWER_COMMAND MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH"
run_test "malformed_result" "RESULT=escalate" "$(line_for RESULT)"
run_test "malformed_reason" "REASON=malformed_output" "$(line_for REASON)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
MOCK_LOCAL_REVIEWER_STDERR='missing model access'
MOCK_LOCAL_REVIEWER_EXIT=1
export LOCAL_AI_REVIEWER_COMMAND MOCK_LOCAL_REVIEWER_STDERR MOCK_LOCAL_REVIEWER_EXIT
run_reviewer "$MOCK_BIN:$PATH"
run_test "missing_model_result" "RESULT=escalate" "$(line_for RESULT)"
run_test "missing_model_reason" "REASON=missing_model_access" "$(line_for REASON)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
MOCK_LOCAL_REVIEWER_STDERR='missing credentials'
MOCK_LOCAL_REVIEWER_EXIT=1
export LOCAL_AI_REVIEWER_COMMAND MOCK_LOCAL_REVIEWER_STDERR MOCK_LOCAL_REVIEWER_EXIT
run_reviewer "$MOCK_BIN:$PATH"
run_test "missing_credentials_result" "RESULT=escalate" "$(line_for RESULT)"
run_test "missing_credentials_reason" "REASON=missing_credentials" "$(line_for REASON)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
LOCAL_AI_REVIEWER_TIMEOUT=1
MOCK_LOCAL_REVIEWER_SLEEP=2
export LOCAL_AI_REVIEWER_COMMAND LOCAL_AI_REVIEWER_TIMEOUT MOCK_LOCAL_REVIEWER_SLEEP
run_reviewer "$MOCK_BIN:$PATH"
run_test "timeout_result" "RESULT=escalate" "$(line_for RESULT)"
run_test "timeout_reason" "REASON=timeout" "$(line_for REASON)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
LOCAL_AI_REVIEWER_GRAPH_STRATEGY=auto
set_mock_stdout '{"result":"clean","findings":[]}'
export LOCAL_AI_REVIEWER_COMMAND LOCAL_AI_REVIEWER_GRAPH_STRATEGY MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$NO_GRAPH_BIN"
run_test "graph_skipped_result" "RESULT=clean" "$(line_for RESULT)"
run_test "graph_skipped_context" "GRAPH_CONTEXT=skipped" "$(line_for GRAPH_CONTEXT)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
set_mock_stdout '{"result":"clean","findings":[]}'
MOCK_PR_HEAD_SHA="0000000000000000000000000000000000000000"
export LOCAL_AI_REVIEWER_COMMAND MOCK_LOCAL_REVIEWER_STDOUT MOCK_PR_HEAD_SHA
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
run_test "head_mismatch_result" "RESULT=escalate" "$(line_for RESULT)"
run_test "head_mismatch_reason" "REASON=head_mismatch" "$(line_for REASON)"

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"
