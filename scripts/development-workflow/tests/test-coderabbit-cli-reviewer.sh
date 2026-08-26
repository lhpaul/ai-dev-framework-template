#!/usr/bin/env bash
# Unit tests for coderabbit-cli-reviewer.sh.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
REVIEWER="$REPO_ROOT/scripts/development-workflow/coderabbit-cli-reviewer.sh"

if [ ! -f "$REVIEWER" ]; then
  echo "ERROR: coderabbit-cli-reviewer.sh not found at $REVIEWER" >&2
  exit 1
fi

MOCK_BIN="$(mktemp -d)"
NO_CLI_BIN="$(mktemp -d)"
CALL_LOG="$(mktemp)"
OUTPUT_FILE="$(mktemp)"
STDERR_FILE="$(mktemp)"
EXIT_FILE="$(mktemp)"
POLICY_CONFIG_FILE="$(mktemp)"
LOCAL_CONFIG_ROOT="$(mktemp -d)"
VALID_REPO_ROOT="$(mktemp -d)"
MISMATCH_REPO_ROOT="$(mktemp -d)"

cleanup() {
  local status=$?
  rm -rf "$MOCK_BIN" "$NO_CLI_BIN" "$LOCAL_CONFIG_ROOT" "$VALID_REPO_ROOT" "$MISMATCH_REPO_ROOT"
  rm -f "$CALL_LOG" "$OUTPUT_FILE" "$STDERR_FILE" "$EXIT_FILE" "$POLICY_CONFIG_FILE"
  exit "$status"
}
trap cleanup EXIT

for _cmd in awk bash cat dirname grep jq mktemp rm sleep tr; do
  _cmd_path="$(command -v "$_cmd")"
  ln -sf "$_cmd_path" "$NO_CLI_BIN/$_cmd"
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
  cat > "$1/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view 123"*"--json baseRefName,headRefName,headRefOid"*)
    if [ "${MOCK_GH_PR_VIEW_FAIL:-0}" = "1" ]; then
      exit 1
    fi
    if [ -n "${MOCK_PR_HEAD_SHA:-}" ]; then
      mock_head_sha="$MOCK_PR_HEAD_SHA"
    elif ! mock_head_sha="$(git rev-parse HEAD 2>/dev/null)"; then
      mock_head_sha=""
    fi
    printf '{"baseRefName":"main","headRefName":"feature/test","headRefOid":"%s"}\n' "$mock_head_sha"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
MOCK_GH
  chmod +x "$1/gh"
}

install_cli_mock() {
  local target="$1"
  cat > "$MOCK_BIN/$target" <<'MOCK_CLI'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "$MOCK_CALL_LOG"
if [ -n "${MOCK_CODERABBIT_STDERR:-}" ]; then
  printf '%s\n' "$MOCK_CODERABBIT_STDERR" >&2
fi
if [ -n "${MOCK_CODERABBIT_SLEEP:-}" ]; then
  sleep "$MOCK_CODERABBIT_SLEEP"
fi
if [ -n "${MOCK_CODERABBIT_STDOUT:-}" ]; then
  printf '%s\n' "$MOCK_CODERABBIT_STDOUT"
fi
exit "${MOCK_CODERABBIT_EXIT:-0}"
MOCK_CLI
  chmod +x "$MOCK_BIN/$target"
}

reset_mocks() {
  rm -f "$CALL_LOG" "$OUTPUT_FILE" "$STDERR_FILE" "$EXIT_FILE"
  CALL_LOG="$(mktemp)"
  OUTPUT_FILE="$(mktemp)"
  STDERR_FILE="$(mktemp)"
  EXIT_FILE="$(mktemp)"
  rm -f "$MOCK_BIN/cr" "$MOCK_BIN/coderabbit" "$MOCK_BIN/gh"
  install_gh_mock "$MOCK_BIN"
  install_cli_mock cr
  install_cli_mock coderabbit
  export MOCK_CALL_LOG
  unset MOCK_CODERABBIT_STDOUT MOCK_CODERABBIT_STDERR MOCK_CODERABBIT_EXIT MOCK_CODERABBIT_SLEEP
  unset MOCK_GH_PR_VIEW_FAIL
  unset CODERABBIT_CLI_RATE_LIMIT_POLICY CODERABBIT_CLI_REVIEW_TIMEOUT
  unset AI_DEV_WORKFLOW_CONFIG_FILE
  unset WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT
}

set_mock_stdout() {
  MOCK_CODERABBIT_STDOUT="$1"
  export MOCK_CODERABBIT_STDOUT
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

init_repo_root_fixture() {
  local target="$1" origin_url="$2"
  git -C "$target" init -q
  git -C "$target" config user.email "test@example.com"
  git -C "$target" config user.name "Test User"
  printf 'fixture\n' > "$target/README.md"
  git -C "$target" add README.md
  git -C "$target" commit -q -m "test fixture"
  git -C "$target" remote add origin "$origin_url"
}

line_for() {
  local key="$1"
  grep "^${key}=" "$OUTPUT_FILE" | head -n 1 || true
}

exit_code() {
  cat "$EXIT_FILE"
}

init_repo_root_fixture "$VALID_REPO_ROOT" "git@github.com:owner/repo.git"
init_repo_root_fixture "$MISMATCH_REPO_ROOT" "git@github.com:other/repo.git"

reset_mocks
set_mock_stdout '{"findings":[]}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "clean_empty_findings_result" "RESULT=clean" "$(line_for RESULT)"
run_test "clean_empty_findings_comments" "COMMENT_COUNT=0" "$(line_for COMMENT_COUNT)"
run_test "clean_empty_findings_exit" "0" "$(exit_code)"

reset_mocks
set_mock_stdout '{"findings":[]}'
MOCK_PR_HEAD_SHA="0000000000000000000000000000000000000000"
export MOCK_PR_HEAD_SHA
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
unset MOCK_PR_HEAD_SHA
run_test "repo_root_head_mismatch_escalates" "RESULT=escalate" "$(line_for RESULT)"
run_test "repo_root_head_mismatch_reason" "REASON=checkout_head_mismatch" "$(line_for REASON)"
run_test "repo_root_head_mismatch_exit" "2" "$(exit_code)"

reset_mocks
set_mock_stdout '{"findings":[]}'
MOCK_PR_HEAD_SHA="$(git -C "$MISMATCH_REPO_ROOT" rev-parse HEAD)"
export MOCK_PR_HEAD_SHA
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$MISMATCH_REPO_ROOT"
unset MOCK_PR_HEAD_SHA
run_test "repo_root_origin_mismatch_escalates" "RESULT=escalate" "$(line_for RESULT)"
run_test "repo_root_origin_mismatch_reason" "REASON=repo_root_mismatch" "$(line_for REASON)"
run_test "repo_root_origin_mismatch_exit" "2" "$(exit_code)"

reset_mocks
set_mock_stdout '{"findings":[]}'
MOCK_GH_PR_VIEW_FAIL=1
export MOCK_GH_PR_VIEW_FAIL
run_reviewer "$MOCK_BIN:$PATH"
unset MOCK_GH_PR_VIEW_FAIL
run_test "base_branch_unavailable_escalates" "RESULT=escalate" "$(line_for RESULT)"
run_test "base_branch_unavailable_reason" "REASON=base_branch_unavailable" "$(line_for REASON)"
run_test "base_branch_unavailable_exit" "2" "$(exit_code)"

credential_repo_root="$(mktemp -d)"
init_repo_root_fixture "$credential_repo_root" "https://secret-token@github.com/other/repo.git"
reset_mocks
set_mock_stdout '{"findings":[]}'
MOCK_PR_HEAD_SHA="$(git -C "$credential_repo_root" rev-parse HEAD)"
export MOCK_PR_HEAD_SHA
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$credential_repo_root"
unset MOCK_PR_HEAD_SHA
run_test "repo_root_credential_mismatch_escalates" "RESULT=escalate" "$(line_for RESULT)"
run_test "repo_root_credential_mismatch_redacts_token" "no" "$(grep -Fq 'secret-token' "$STDERR_FILE" && echo yes || echo no)"
rm -rf "$credential_repo_root"

credential_userinfo_repo_root="$(mktemp -d)"
init_repo_root_fixture "$credential_userinfo_repo_root" "https://user:secret-token@github.com/other/repo.git"
reset_mocks
set_mock_stdout '{"findings":[]}'
MOCK_PR_HEAD_SHA="$(git -C "$credential_userinfo_repo_root" rev-parse HEAD)"
export MOCK_PR_HEAD_SHA
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$credential_userinfo_repo_root"
unset MOCK_PR_HEAD_SHA
run_test "repo_root_userinfo_credential_mismatch_escalates" "RESULT=escalate" "$(line_for RESULT)"
run_test "repo_root_userinfo_credential_mismatch_redacts_token" "no" "$(grep -Fq 'secret-token' "$STDERR_FILE" && echo yes || echo no)"
rm -rf "$credential_userinfo_repo_root"

reset_mocks
set_mock_stdout '{"findings":[{"severity":"Critical","path":"scripts/example.sh","line":42,"message":"fix this"}]}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "blocking_finding_result" "RESULT=needs_fixes" "$(line_for RESULT)"
run_test "blocking_finding_count" "BLOCKING_COUNT=1" "$(line_for BLOCKING_COUNT)"
run_test "blocking_finding_path" "BLOCKING_1_PATH=scripts/example.sh" "$(line_for BLOCKING_1_PATH)"
run_test "blocking_finding_line" "BLOCKING_1_LINE=42" "$(line_for BLOCKING_1_LINE)"
run_test "blocking_finding_body" "BLOCKING_1_BODY=fix this" "$(line_for BLOCKING_1_BODY)"
run_test "blocking_finding_exit" "1" "$(exit_code)"

reset_mocks
set_mock_stdout '{"findings":[{"severity":"Critical","path":"scripts/example.sh\nINJECTED=1","line":"42\nALSO=1","message":"fix this"}]}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "blocking_finding_path_escaped" "BLOCKING_1_PATH=scripts/example.sh\\nINJECTED=1" "$(line_for BLOCKING_1_PATH)"
run_test "blocking_finding_line_escaped" "BLOCKING_1_LINE=42\\nALSO=1" "$(line_for BLOCKING_1_LINE)"

reset_mocks
set_mock_stdout '{"type":"finding","finding":{"severity":"High","message":"fix this"}}
{"type":"complete","summary":"done"}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "ndjson_blocking_finding_result" "RESULT=needs_fixes" "$(line_for RESULT)"
run_test "ndjson_blocking_finding_count" "BLOCKING_COUNT=1" "$(line_for BLOCKING_COUNT)"

reset_mocks
set_mock_stdout '{"type":"finding","finding":{"severity":"High","path":"scripts/example.sh","line":7,"message":"fix single event"}}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "single_event_blocking_finding_result" "RESULT=needs_fixes" "$(line_for RESULT)"
run_test "single_event_blocking_finding_count" "BLOCKING_COUNT=1" "$(line_for BLOCKING_COUNT)"
run_test "single_event_blocking_finding_path" "BLOCKING_1_PATH=scripts/example.sh" "$(line_for BLOCKING_1_PATH)"

reset_mocks
set_mock_stdout '{"type":"status","message":"review started"}
{"type":"complete","summary":"done"}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "ndjson_no_findings_result" "RESULT=clean" "$(line_for RESULT)"
run_test "ndjson_no_findings_comments" "COMMENT_COUNT=0" "$(line_for COMMENT_COUNT)"

reset_mocks
set_mock_stdout '{"findings":[{"severity":"Minor","message":"consider this"}]}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "advisory_only_result" "RESULT=clean" "$(line_for RESULT)"
run_test "advisory_only_suggestions" "SUGGESTION_COUNT=1" "$(line_for SUGGESTION_COUNT)"

reset_mocks
set_mock_stdout '{"summary":"complete"}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "missing_findings_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "missing_findings_reason" "REASON=invalid_json" "$(line_for REASON)"
run_test "missing_findings_exit" "3" "$(exit_code)"

reset_mocks
set_mock_stdout '{"summary":"authentication docs mention login behavior"}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "missing_findings_auth_text_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "missing_findings_auth_text_reason" "REASON=invalid_json" "$(line_for REASON)"

reset_mocks
set_mock_stdout '{"error":"HTTP 429 rate limit exceeded"}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "json_rate_limit_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "json_rate_limit_reason" "REASON=rate_limited" "$(line_for REASON)"

reset_mocks
set_mock_stdout '{"findings":[],"error":"HTTP 429 rate limit exceeded"}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "empty_findings_json_rate_limit_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "empty_findings_json_rate_limit_reason" "REASON=rate_limited" "$(line_for REASON)"

reset_mocks
set_mock_stdout '{"error":"Unauthorized. Run coderabbit auth login --agent."}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "json_unauthorized_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "json_unauthorized_reason" "REASON=unauthorized" "$(line_for REASON)"

reset_mocks
set_mock_stdout '{"findings":[],"error":"Unauthorized. Run coderabbit auth login --agent."}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "empty_findings_json_unauthorized_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "empty_findings_json_unauthorized_reason" "REASON=unauthorized" "$(line_for REASON)"

reset_mocks
set_mock_stdout '{"findings":[{"severity":"Needs Triage","message":"unclear"}]}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "ambiguous_finding_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "ambiguous_finding_reason" "REASON=ambiguous_output" "$(line_for REASON)"

reset_mocks
set_mock_stdout 'not json'
run_reviewer "$MOCK_BIN:$PATH"
run_test "invalid_json_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "invalid_json_reason" "REASON=invalid_json" "$(line_for REASON)"

reset_mocks
MOCK_CODERABBIT_STDOUT=''
MOCK_CODERABBIT_STDERR='HTTP 429 rate limit exceeded'
MOCK_CODERABBIT_EXIT=1
export MOCK_CODERABBIT_STDOUT MOCK_CODERABBIT_STDERR MOCK_CODERABBIT_EXIT
run_reviewer "$MOCK_BIN:$PATH"
run_test "rate_limit_warn_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "rate_limit_warn_reason" "REASON=rate_limited" "$(line_for REASON)"
run_test "rate_limit_warn_display" "DISPLAY_RESULT=rate_limited" "$(line_for DISPLAY_RESULT)"
run_test "rate_limit_warn_exit" "3" "$(exit_code)"

reset_mocks
MOCK_CODERABBIT_STDERR='too many requests'
MOCK_CODERABBIT_EXIT=1
CODERABBIT_CLI_RATE_LIMIT_POLICY=strict
export MOCK_CODERABBIT_STDERR MOCK_CODERABBIT_EXIT CODERABBIT_CLI_RATE_LIMIT_POLICY
run_reviewer "$MOCK_BIN:$PATH"
run_test "rate_limit_strict_result" "RESULT=escalate" "$(line_for RESULT)"
run_test "rate_limit_strict_reason" "REASON=rate_limited" "$(line_for REASON)"
run_test "rate_limit_strict_exit" "2" "$(exit_code)"

reset_mocks
set_mock_stdout '{"findings":[{"severity":"Minor","message":"mentions HTTP 429 inside a finding body"}]}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "rate_limit_text_inside_json_result" "RESULT=clean" "$(line_for RESULT)"
run_test "rate_limit_text_inside_json_suggestions" "SUGGESTION_COUNT=1" "$(line_for SUGGESTION_COUNT)"

reset_mocks
set_mock_stdout '{"findings":[]}'
MOCK_CODERABBIT_STDERR='HTTP 429 rate limit exceeded'
export MOCK_CODERABBIT_STDERR
run_reviewer "$MOCK_BIN:$PATH"
run_test "rate_limit_stderr_with_json_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "rate_limit_stderr_with_json_reason" "REASON=rate_limited" "$(line_for REASON)"

reset_mocks
set_mock_stdout '{"findings":[]}'
MOCK_CODERABBIT_STDERR='author metadata: login hint is informational'
export MOCK_CODERABBIT_STDERR
run_reviewer "$MOCK_BIN:$PATH"
run_test "benign_auth_like_stderr_with_json_result" "RESULT=clean" "$(line_for RESULT)"

reset_mocks
set_mock_stdout '{"findings":[{"severity":"Critical","message":"fix this"}]}'
MOCK_CODERABBIT_STDERR='HTTP 429 rate limit exceeded'
export MOCK_CODERABBIT_STDERR
run_reviewer "$MOCK_BIN:$PATH"
run_test "blocking_json_with_rate_limit_stderr_result" "RESULT=needs_fixes" "$(line_for RESULT)"
run_test "blocking_json_with_rate_limit_stderr_exit" "1" "$(exit_code)"

reset_mocks
cat > "$POLICY_CONFIG_FILE" <<'YAML'
review:
  coderabbit_cli:
    rate_limit_policy: strict
YAML
set_mock_stdout '{"findings":[]}'
MOCK_CODERABBIT_STDERR='HTTP 429 rate limit exceeded'
AI_DEV_WORKFLOW_CONFIG_FILE="$POLICY_CONFIG_FILE"
export MOCK_CODERABBIT_STDERR AI_DEV_WORKFLOW_CONFIG_FILE
run_reviewer "$MOCK_BIN:$PATH"
run_test "rate_limit_policy_effective_config_result" "RESULT=escalate" "$(line_for RESULT)"
run_test "rate_limit_policy_effective_config_exit" "2" "$(exit_code)"

reset_mocks
cat > "$LOCAL_CONFIG_ROOT/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  coderabbit_cli:
    rate_limit_policy: strict
YAML
set_mock_stdout '{"findings":[]}'
MOCK_CODERABBIT_STDERR='HTTP 429 rate limit exceeded'
WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$LOCAL_CONFIG_ROOT"
export MOCK_CODERABBIT_STDERR WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT
run_reviewer "$MOCK_BIN:$PATH"
run_test "rate_limit_policy_local_config_result" "RESULT=escalate" "$(line_for RESULT)"
run_test "rate_limit_policy_local_config_exit" "2" "$(exit_code)"

reset_mocks
set_mock_stdout '{"findings":[]}'
MOCK_CODERABBIT_SLEEP=2
CODERABBIT_CLI_REVIEW_TIMEOUT=1
export MOCK_CODERABBIT_SLEEP CODERABBIT_CLI_REVIEW_TIMEOUT
run_reviewer "$MOCK_BIN:$NO_CLI_BIN"
run_test "fallback_timeout_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "fallback_timeout_reason" "REASON=timeout" "$(line_for REASON)"
run_test "fallback_timeout_exit" "3" "$(exit_code)"

reset_mocks
set_mock_stdout '{"findings":[{"severity":"Minor"},{"severity":"Critical"}]}'
MOCK_CODERABBIT_EXIT=7
export MOCK_CODERABBIT_EXIT
run_reviewer "$MOCK_BIN:$PATH"
run_test "nonzero_valid_json_result" "RESULT=needs_fixes" "$(line_for RESULT)"
run_test "nonzero_valid_json_exit" "1" "$(exit_code)"

reset_mocks
set_mock_stdout '{"findings":[]}'
MOCK_CODERABBIT_EXIT=7
export MOCK_CODERABBIT_EXIT
run_reviewer "$MOCK_BIN:$PATH"
run_test "nonzero_clean_json_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "nonzero_clean_json_reason" "REASON=cli_failed" "$(line_for REASON)"
run_test "nonzero_clean_json_exit" "3" "$(exit_code)"

reset_mocks
MOCK_CODERABBIT_STDOUT=''
MOCK_CODERABBIT_EXIT=1
export MOCK_CODERABBIT_STDOUT MOCK_CODERABBIT_EXIT
run_reviewer "$MOCK_BIN:$PATH"
run_test "nonzero_empty_output_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "nonzero_empty_output_exit" "3" "$(exit_code)"

reset_mocks
set_mock_stdout '{"findings":[{"severity":"Low"},{"severity":"Major"},{"severity":"Nitpick"}]}'
run_reviewer "$MOCK_BIN:$PATH"
run_test "multiple_findings_result" "RESULT=needs_fixes" "$(line_for RESULT)"
run_test "multiple_findings_blocking" "BLOCKING_COUNT=1" "$(line_for BLOCKING_COUNT)"
run_test "multiple_findings_suggestions" "SUGGESTION_COUNT=2" "$(line_for SUGGESTION_COUNT)"

reset_mocks
set_mock_stdout '[{"severity":"Low"},{"severity":"Minor"}]'
run_reviewer "$MOCK_BIN:$PATH"
run_test "top_level_array_result" "RESULT=clean" "$(line_for RESULT)"
run_test "top_level_array_suggestions" "SUGGESTION_COUNT=2" "$(line_for SUGGESTION_COUNT)"

reset_mocks
rm -f "$MOCK_BIN/cr"
set_mock_stdout '{"findings":[]}'
run_reviewer "$MOCK_BIN:$NO_CLI_BIN"
run_test "fallback_coderabbit_result" "RESULT=clean" "$(line_for RESULT)"
run_test "fallback_coderabbit_command" "CLI_COMMAND=coderabbit" "$(line_for CLI_COMMAND)"
run_test "fallback_coderabbit_base" "BASE_BRANCH=main" "$(line_for BASE_BRANCH)"

reset_mocks
run_reviewer "$NO_CLI_BIN"
run_test "missing_cli_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "missing_cli_reason" "REASON=unavailable" "$(line_for REASON)"
run_test "missing_cli_exit" "3" "$(exit_code)"

reset_mocks
MOCK_CODERABBIT_STDERR='Unauthorized, run coderabbit auth login --agent'
MOCK_CODERABBIT_EXIT=1
export MOCK_CODERABBIT_STDERR MOCK_CODERABBIT_EXIT
run_reviewer "$MOCK_BIN:$PATH"
run_test "unauthorized_result" "RESULT=skipped" "$(line_for RESULT)"
run_test "unauthorized_reason" "REASON=unauthorized" "$(line_for REASON)"

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"
