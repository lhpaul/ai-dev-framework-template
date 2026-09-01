#!/usr/bin/env bash
# Unit tests for local-ai-reviewer.sh.
# covers: scripts/development-workflow/local-ai-reviewer.sh
# shellcheck disable=SC2089,SC2090

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
REVIEWER="$REPO_ROOT/scripts/development-workflow/local-ai-reviewer.sh"

MOCK_BIN="$(mktemp -d)"
NO_GRAPH_BIN="$(mktemp -d)"
FALLBACK_BIN="$(mktemp -d)"
OUTPUT_FILE="$(mktemp)"
STDERR_FILE="$(mktemp)"
EXIT_FILE="$(mktemp)"
EVIDENCE_FILE="$(mktemp)"
RELATIVE_EVIDENCE_FILE="local-ai-reviewer-relative-evidence.json"
VALID_REPO_ROOT="$(mktemp -d)"

cleanup() {
  local status=$?
  rm -rf "$MOCK_BIN" "$NO_GRAPH_BIN" "$FALLBACK_BIN" "$VALID_REPO_ROOT"
  rm -f "$OUTPUT_FILE" "$STDERR_FILE" "$EXIT_FILE" "$EVIDENCE_FILE" "$RELATIVE_EVIDENCE_FILE"
  exit "$status"
}
trap cleanup EXIT

for _cmd in awk bash cat date dirname git grep jq mktemp perl rm sed sh sleep tr; do
  _cmd_path="$(command -v "$_cmd")"
  [ -n "$_cmd_path" ] || continue
  ln -sf "$_cmd_path" "$NO_GRAPH_BIN/$_cmd"
  ln -sf "$_cmd_path" "$FALLBACK_BIN/$_cmd"
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
    mock_head_branch="${MOCK_PR_HEAD_BRANCH:-feature/test}"
    printf '{"baseRefName":"develop","headRefName":"%s","headRefOid":"%s"}\n' "$mock_head_branch" "$mock_head_sha"
    exit 0
    ;;
  *"pr diff 123"*"--name-only"*)
    if [ "${MOCK_PR_DIFF_EXIT:-0}" -ne 0 ]; then
      exit "$MOCK_PR_DIFF_EXIT"
    fi
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
if [ -n "${MOCK_LOCAL_REVIEWER_GRANDCHILD_PIDFILE:-}" ]; then
  sleep 30 &
  printf '%s\n' "$!" > "$MOCK_LOCAL_REVIEWER_GRANDCHILD_PIDFILE"
  wait
fi
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
  unset MOCK_PR_HEAD_SHA MOCK_PR_DIFF_EXIT MOCK_LOCAL_REVIEWER_STDOUT MOCK_LOCAL_REVIEWER_STDERR
  unset MOCK_LOCAL_REVIEWER_EXIT MOCK_LOCAL_REVIEWER_SLEEP
  unset MOCK_LOCAL_REVIEWER_GRANDCHILD_PIDFILE MOCK_PR_HEAD_BRANCH
  unset LOCAL_AI_REVIEWER_COMMAND LOCAL_AI_REVIEWER_DISABLED LOCAL_AI_REVIEWER_TIMEOUT
  unset LOCAL_AI_REVIEWER_EVIDENCE_FILE LOCAL_AI_REVIEWER_GRAPH_STRATEGY
  unset LOCAL_AI_REVIEWER_DISABLE_DEFAULT
  unset MOCK_STRICT_STDOUT MOCK_ORDINARY_STDOUT MOCK_STRICT_EXIT MOCK_ORDINARY_SLEEP
  unset MOCK_RECORD_FILE MOCK_ORDINARY_EXIT
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
LOCAL_AI_REVIEWER_DISABLE_DEFAULT=1
export LOCAL_AI_REVIEWER_DISABLE_DEFAULT
run_reviewer "$MOCK_BIN:$PATH"
run_test "missing_command_result" "RESULT=escalate" "$(line_for RESULT)"
run_test "missing_command_reason" "REASON=missing_command" "$(line_for REASON)"
run_test "missing_command_exit" "2" "$(exit_code)"

reset_mocks
cat > "$MOCK_BIN/codex" <<'MOCK_CODEX'
#!/usr/bin/env bash
output_file=""
previous=""
for arg in "$@"; do
  if [ "$previous" = "-o" ]; then
    output_file="$arg"
  fi
  previous="$arg"
done
[ -n "$output_file" ] || exit 2
printf '{"result":"clean","reviewed_head":"%s","findings":[]}\n' "${REVIEWED_HEAD:?}" > "$output_file"
MOCK_CODEX
chmod +x "$MOCK_BIN/codex"
run_reviewer "$MOCK_BIN:$PATH"
run_test "default_command_result" "RESULT=clean" "$(line_for RESULT)"
run_test "default_command_info" "yes" "$(grep -q 'LOCAL_AI_REVIEWER_COMMAND defaulted to bundled Codex preset' "$STDERR_FILE" && echo yes || echo no)"

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
MOCK_LOCAL_REVIEWER_STDERR='missing model access warning in non-authoritative stderr'
set_mock_stdout '{"result":"clean","findings":[]}'
export LOCAL_AI_REVIEWER_COMMAND MOCK_LOCAL_REVIEWER_STDERR MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH"
run_test "clean_json_ignores_nonfatal_stderr_probe" "RESULT=clean" "$(line_for RESULT)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
LOCAL_AI_REVIEWER_EVIDENCE_FILE="$EVIDENCE_FILE"
set_mock_stdout '{"result":"clean","findings":[]}'
export LOCAL_AI_REVIEWER_COMMAND LOCAL_AI_REVIEWER_EVIDENCE_FILE MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH"
run_test "evidence_schema" "local_ai_reviewer_evidence.v1" "$(jq -r '.schema_version' "$EVIDENCE_FILE")"
run_test "evidence_result" "clean" "$(jq -r '.result' "$EVIDENCE_FILE")"
run_test "evidence_changed_file" "scripts/example.sh" "$(jq -r '.context_summary.changed_files[0]' "$EVIDENCE_FILE")"

reset_mocks
rm -f "$RELATIVE_EVIDENCE_FILE" "$VALID_REPO_ROOT/$RELATIVE_EVIDENCE_FILE"
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
LOCAL_AI_REVIEWER_EVIDENCE_FILE="$RELATIVE_EVIDENCE_FILE"
MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
set_mock_stdout '{"result":"clean","findings":[]}'
export LOCAL_AI_REVIEWER_COMMAND LOCAL_AI_REVIEWER_EVIDENCE_FILE MOCK_LOCAL_REVIEWER_STDOUT MOCK_PR_HEAD_SHA
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
run_test "relative_evidence_path_uses_original_cwd" "yes" "$([ -f "$RELATIVE_EVIDENCE_FILE" ] && [ ! -f "$VALID_REPO_ROOT/$RELATIVE_EVIDENCE_FILE" ] && echo yes || echo no)"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
LOCAL_AI_REVIEWER_EVIDENCE_FILE="$VALID_REPO_ROOT/missing-dir/evidence.json"
set_mock_stdout '{"result":"clean","findings":[]}'
export LOCAL_AI_REVIEWER_COMMAND LOCAL_AI_REVIEWER_EVIDENCE_FILE MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH"
run_test "unwritable_evidence_path_preserves_result" "RESULT=clean" "$(line_for RESULT)"

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
set_mock_stdout '{"findings":[{"severity":"important","path":"scripts/example.sh","line":42,"message":"unauthorized text in a real finding"}]}'
export LOCAL_AI_REVIEWER_COMMAND MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH"
run_test "finding_text_does_not_trigger_auth_escalation_result" "RESULT=needs_fixes" "$(line_for RESULT)"
run_test "blocking_detail_path" "BLOCKING_1_PATH=scripts/example.sh" "$(line_for BLOCKING_1_PATH)"
run_test "blocking_detail_line" "BLOCKING_1_LINE=42" "$(line_for BLOCKING_1_LINE)"
run_test "blocking_detail_body" "BLOCKING_1_BODY=unauthorized text in a real finding" "$(line_for BLOCKING_1_BODY)"

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
MOCK_PR_DIFF_EXIT=1
set_mock_stdout '{"result":"clean","findings":[]}'
export LOCAL_AI_REVIEWER_COMMAND MOCK_PR_DIFF_EXIT MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH"
run_test "diff_unavailable_result" "RESULT=escalate" "$(line_for RESULT)"
run_test "diff_unavailable_reason" "REASON=diff_unavailable" "$(line_for REASON)"

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
LOCAL_AI_REVIEWER_TIMEOUT=1
MOCK_LOCAL_REVIEWER_GRANDCHILD_PIDFILE="$(mktemp)"
export LOCAL_AI_REVIEWER_COMMAND LOCAL_AI_REVIEWER_TIMEOUT MOCK_LOCAL_REVIEWER_GRANDCHILD_PIDFILE
run_reviewer "$MOCK_BIN:$FALLBACK_BIN"
run_test "fallback_timeout_result" "RESULT=escalate" "$(line_for RESULT)"
run_test "fallback_timeout_reason" "REASON=timeout" "$(line_for REASON)"
_grandchild_pid=""
if [ -s "$MOCK_LOCAL_REVIEWER_GRANDCHILD_PIDFILE" ]; then
  _grandchild_pid="$(cat "$MOCK_LOCAL_REVIEWER_GRANDCHILD_PIDFILE")"
fi
_grandchild_alive=0
if [ -n "$_grandchild_pid" ] && kill -0 "$_grandchild_pid" 2>/dev/null; then
  _grandchild_alive=1
  kill -KILL "$_grandchild_pid" 2>/dev/null || true
fi
run_test "fallback_timeout_kills_grandchild" "0" "$_grandchild_alive"
rm -f "$MOCK_LOCAL_REVIEWER_GRANDCHILD_PIDFILE"
unset MOCK_LOCAL_REVIEWER_GRANDCHILD_PIDFILE _grandchild_pid _grandchild_alive

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

# ---------------------------------------------------------------------------
# Strict spec contract checks (#1650) — scenarios 1–13
# ---------------------------------------------------------------------------

FIXTURES="$REPO_ROOT/scripts/development-workflow/tests/fixtures"
CHECKLIST_FIXTURES="$FIXTURES/strict-spec-checks"
SHIPPED_CHECKLIST="$REPO_ROOT/docs/workflow/development-workflow/strict-spec-checks.md"

key_present() {
  grep -q "^${1}=" "$OUTPUT_FILE" && echo yes || echo no
}

install_checklist_into_repo() {
  local src="$1"
  mkdir -p "$VALID_REPO_ROOT/docs/workflow/development-workflow"
  cp "$src" "$VALID_REPO_ROOT/docs/workflow/development-workflow/strict-spec-checks.md"
  git -C "$VALID_REPO_ROOT" add docs/workflow/development-workflow/strict-spec-checks.md >/dev/null 2>&1 || true # workflow-shell-guard: allow SH001 - fixture add is best-effort for spec-stage tests
}

remove_checklist_from_repo() {
  rm -f "$VALID_REPO_ROOT/docs/workflow/development-workflow/strict-spec-checks.md"
}

install_recording_two_pass_mock() {
  cat > "$MOCK_BIN/local-reviewer-mock" <<'MOCK_REVIEWER'
#!/usr/bin/env bash
mode="${LOCAL_AI_REVIEWER_MODE:-ordinary}"
if [ -n "${MOCK_RECORD_FILE:-}" ]; then
  {
    printf 'mode=%s\n' "$mode"
    if [ -n "${CONTEXT_BUNDLE_PATH:-}" ] && [ -f "${CONTEXT_BUNDLE_PATH}" ]; then
      printf 'bundle_keys=%s\n' "$(jq -r 'keys | join(",")' "$CONTEXT_BUNDLE_PATH")"
      printf 'has_strict_spec_checks=%s\n' "$(jq -r 'has("strict_spec_checks")' "$CONTEXT_BUNDLE_PATH")"
      printf 'has_strict_plan_checks=%s\n' "$(jq -r 'has("strict_plan_checks")' "$CONTEXT_BUNDLE_PATH")"
      printf 'has_strict_plan_documents=%s\n' "$(jq -r 'has("strict_plan_documents")' "$CONTEXT_BUNDLE_PATH")"
    fi
  } >> "$MOCK_RECORD_FILE"
fi
if [ "$mode" = "strict" ]; then
  if [ -n "${MOCK_ORDINARY_SLEEP:-}" ] && [ "${MOCK_STRICT_SLEEP_EXTRA:-0}" != "0" ]; then
    sleep "${MOCK_STRICT_SLEEP_EXTRA}"
  fi
  if [ -n "${MOCK_STRICT_STDOUT:-}" ]; then
    printf '%s\n' "$MOCK_STRICT_STDOUT"
  fi
  exit "${MOCK_STRICT_EXIT:-0}"
fi
if [ -n "${MOCK_ORDINARY_SLEEP:-}" ]; then
  sleep "$MOCK_ORDINARY_SLEEP"
fi
if [ -n "${MOCK_ORDINARY_STDOUT:-}" ]; then
  printf '%s\n' "$MOCK_ORDINARY_STDOUT"
elif [ -n "${MOCK_LOCAL_REVIEWER_STDOUT:-}" ]; then
  printf '%s\n' "$MOCK_LOCAL_REVIEWER_STDOUT"
fi
exit "${MOCK_ORDINARY_EXIT:-0}"
MOCK_REVIEWER
  chmod +x "$MOCK_BIN/local-reviewer-mock"
}

run_spec_review() {
  MOCK_PR_HEAD_BRANCH="${MOCK_PR_HEAD_BRANCH:-spec/1650-test}"
  MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
  export MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
  LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
  export LOCAL_AI_REVIEWER_COMMAND
  run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT" "$@"
}

# Scenario 13d: shipped identifiers match the spec set
EXPECTED_IDS='["ac_consistency","ac_testability","gate_matrix","opt_out_source","trigger_semantics","example_contradiction","parser_surface","ambiguous_phrase"]'
EXTRACTED_IDS="$(
  HARNESS_MODE=1 bash -c '
    source "'"$REVIEWER"'"
    extract_strict_spec_known_checks "'"$SHIPPED_CHECKLIST"'"
  ' | jq -c 'sort'
)"
run_test "s13d_shipped_ids_match_spec" "$(printf '%s\n' "$EXPECTED_IDS" | jq -c 'sort')" "$EXTRACTED_IDS"

# Scenario 9d: no second timeout setting
run_test "s9d_no_strict_timeout_name" "yes" \
  "$(grep -Eq 'LOCAL_AI_REVIEWER_STRICT_TIMEOUT|STRICT_SPEC_TIMEOUT' "$REVIEWER" >/dev/null && echo no || echo yes)"
run_test "s9d_help_no_second_timeout_knob" "yes" \
  "$(bash "$REVIEWER" --help 2>&1 | grep -Eq 'LOCAL_AI_REVIEWER_STRICT_TIMEOUT|STRICT_SPEC_TIMEOUT' && echo no || echo yes)"

# --- Matrix rows via full runs ---
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"

# Row 2: not_applicable (feature branch) — exactly 1 invocation
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_RECORD_FILE="$(mktemp)"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_PR_HEAD_BRANCH="feature/test"
MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
export MOCK_RECORD_FILE MOCK_ORDINARY_STDOUT MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
export LOCAL_AI_REVIEWER_COMMAND
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
run_test "s1_row2_state" "STRICT_SPEC_STATE=not_applicable" "$(line_for STRICT_SPEC_STATE)"
run_test "s1a_row2_no_reason" "no" "$(key_present STRICT_SPEC_REASON)"
run_test "s2_row2_no_count" "no" "$(key_present STRICT_SPEC_COUNT)"
run_test "s2_row2_no_checks" "no" "$(key_present STRICT_SPEC_CHECKS)"
run_test "s9b_row2_invocations" "1" "$(grep -c '^mode=' "$MOCK_RECORD_FILE" || true)"
run_test "s11a_row2_mode_ordinary" "mode=ordinary" "$(grep '^mode=' "$MOCK_RECORD_FILE" | head -1)"
rm -f "$MOCK_RECORD_FILE"

# Row 1: stage_unresolved (empty HEAD_BRANCH)
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_RECORD_FILE="$(mktemp)"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_PR_HEAD_BRANCH=""
MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
export MOCK_RECORD_FILE MOCK_ORDINARY_STDOUT MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
export LOCAL_AI_REVIEWER_COMMAND
# Empty headRefName in gh mock
cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view 123"*"--json baseRefName,headRefName,headRefOid"*)
    printf '{"baseRefName":"develop","headRefName":"","headRefOid":"%s"}\n' "${MOCK_PR_HEAD_SHA}"
    exit 0
    ;;
  *"pr diff 123"*"--name-only"*)
    printf 'scripts/example.sh\n'
    exit 0
    ;;
  *) exit 1 ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
run_test "s1_row1_state" "STRICT_SPEC_STATE=unavailable" "$(line_for STRICT_SPEC_STATE)"
run_test "s1a_row1_reason" "STRICT_SPEC_REASON=stage_unresolved" "$(line_for STRICT_SPEC_REASON)"
run_test "s2_row1_no_count" "no" "$(key_present STRICT_SPEC_COUNT)"
run_test "s9b_row1_invocations" "1" "$(grep -c '^mode=' "$MOCK_RECORD_FILE" || true)"
rm -f "$MOCK_RECORD_FILE"

# Row 3: checklist_unreadable
reset_mocks
install_recording_two_pass_mock
remove_checklist_from_repo
MOCK_RECORD_FILE="$(mktemp)"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
export MOCK_RECORD_FILE MOCK_ORDINARY_STDOUT
run_spec_review
run_test "s1_row3_state" "STRICT_SPEC_STATE=unavailable" "$(line_for STRICT_SPEC_STATE)"
run_test "s1a_row3_reason" "STRICT_SPEC_REASON=checklist_unreadable" "$(line_for STRICT_SPEC_REASON)"
run_test "s2_row3_no_count" "no" "$(key_present STRICT_SPEC_COUNT)"
run_test "s9b_row3_invocations" "1" "$(grep -c '^mode=' "$MOCK_RECORD_FILE" || true)"
rm -f "$MOCK_RECORD_FILE"

# Row 5: applied count 0
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_RECORD_FILE="$(mktemp)"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","findings":[]}'
export MOCK_RECORD_FILE MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s1_row5_state" "STRICT_SPEC_STATE=applied" "$(line_for STRICT_SPEC_STATE)"
run_test "s1_row5_count0" "STRICT_SPEC_COUNT=0" "$(line_for STRICT_SPEC_COUNT)"
run_test "s1_row5_checks_empty" "STRICT_SPEC_CHECKS=" "$(line_for STRICT_SPEC_CHECKS)"
run_test "s1a_row5_no_reason" "no" "$(key_present STRICT_SPEC_REASON)"
run_test "s3_applied0_vs_unavailable" "applied" "$(grep '^STRICT_SPEC_STATE=' "$OUTPUT_FILE" | cut -d= -f2)"
run_test "s9b_row5_invocations" "2" "$(grep -c '^mode=' "$MOCK_RECORD_FILE" || true)"
run_test "s11a_modes" "ordinary,strict" "$(awk -F= '/^mode=/{printf "%s%s", (n++?",":""), $2} END{print ""}' "$MOCK_RECORD_FILE")"
run_test "s11_ordinary_bundle_no_strict_key" "false" \
  "$(awk -F= '/^has_strict_spec_checks=/{print $2; exit}' "$MOCK_RECORD_FILE")"
run_test "s11_strict_bundle_has_key" "true" \
  "$(awk -F= '/^has_strict_spec_checks=/{print $2}' "$MOCK_RECORD_FILE" | tail -1)"
rm -f "$MOCK_RECORD_FILE"

# Scenario 5a / row 6 / scenarios 4,8,9: findings
THREE_STRICT='{"mode":"strict_spec_checks","findings":[{"check":"ac_consistency","path":"spec.md","line":1,"body":"contradiction A"},{"check":"gate_matrix","path":"spec.md","line":2,"body":"missing combo"},{"check":"ac_consistency","path":"spec.md","line":3,"body":"contradiction B"}]}'
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT="$THREE_STRICT"
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s9_clean_with_strict_result" "RESULT=clean" "$(line_for RESULT)"
run_test "s9_blocking_zero" "BLOCKING_COUNT=0" "$(line_for BLOCKING_COUNT)"
run_test "s9_strict_count3" "STRICT_SPEC_COUNT=3" "$(line_for STRICT_SPEC_COUNT)"
run_test "s4_no_blocking_detail" "no" "$(key_present BLOCKING_1_PATH)"
run_test "s4_strict_detail_check" "STRICT_1_CHECK=ac_consistency" "$(line_for STRICT_1_CHECK)"
run_test "s10_distinct_checks" "STRICT_SPEC_CHECKS=ac_consistency,gate_matrix" "$(line_for STRICT_SPEC_CHECKS)"

# Scenario 5a: same ordinary output with checklist removed
ORDINARY_WITH_STRICT="$(grep -E '^(RESULT|COMMENT_COUNT|BLOCKING_COUNT|SUGGESTION_COUNT|BLOCKING_[0-9]+_)' "$OUTPUT_FILE" || true)"
reset_mocks
install_recording_two_pass_mock
remove_checklist_from_repo
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT="$THREE_STRICT"
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
ORDINARY_WITHOUT="$(grep -E '^(RESULT|COMMENT_COUNT|BLOCKING_COUNT|SUGGESTION_COUNT|BLOCKING_[0-9]+_)' "$OUTPUT_FILE" || true)"
run_test "s5a_ordinary_identical" "$ORDINARY_WITH_STRICT" "$ORDINARY_WITHOUT"
run_test "s5a_unavailable" "STRICT_SPEC_STATE=unavailable" "$(line_for STRICT_SPEC_STATE)"

# Scenario 8: mixed blocking + strict
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"needs_fixes","findings":[{"severity":"important","path":"a.sh","line":1,"message":"b1"},{"severity":"important","path":"b.sh","line":2,"message":"b2"}]}'
MOCK_STRICT_STDOUT="$THREE_STRICT"
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s8_result" "RESULT=needs_fixes" "$(line_for RESULT)"
run_test "s8_blocking" "BLOCKING_COUNT=2" "$(line_for BLOCKING_COUNT)"
run_test "s8_strict" "STRICT_SPEC_COUNT=3" "$(line_for STRICT_SPEC_COUNT)"

# Scenario 8a: strict result ignored
FIXED_ORDINARY='{"result":"clean","findings":[]}'
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT="$FIXED_ORDINARY"
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","result":"needs_fixes","findings":[{"check":"ac_consistency","path":"s.md","line":1,"body":"x"}]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
R1="$(line_for RESULT)"
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT="$FIXED_ORDINARY"
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","result":"clean","findings":[{"check":"ac_consistency","path":"s.md","line":1,"body":"x"}]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
R2="$(line_for RESULT)"
run_test "s8a_result_identical" "$R1" "$R2"
run_test "s8a_result_clean" "RESULT=clean" "$R1"

# Scenario 6: unknown identifier
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","findings":[{"check":"not_a_real_check","path":"s.md","line":1,"body":"x"},{"check":"ac_consistency","path":"s.md","line":2,"body":"y"}]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s6_count_excludes_unknown" "STRICT_SPEC_COUNT=1" "$(line_for STRICT_SPEC_COUNT)"
run_test "s6_unknown_count" "STRICT_SPEC_UNKNOWN_COUNT=1" "$(line_for STRICT_SPEC_UNKNOWN_COUNT)"
run_test "s6_unknown_label" "STRICT_1_CHECK=unknown" "$(line_for STRICT_1_CHECK)"
run_test "s6_not_blocking" "BLOCKING_COUNT=0" "$(line_for BLOCKING_COUNT)"
run_test "s6_result_clean" "RESULT=clean" "$(line_for RESULT)"

# Scenario 7: non-string / missing check
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","findings":[{"check":12,"path":"s.md","line":1,"body":"n"},{"check":{"x":1},"path":"s.md","line":2,"body":"o"},{"check":null,"path":"s.md","line":3,"body":"z"},{"path":"s.md","line":4,"body":"missing"}]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s7_all_unknown" "STRICT_SPEC_UNKNOWN_COUNT=4" "$(line_for STRICT_SPEC_UNKNOWN_COUNT)"
run_test "s7_count_zero" "STRICT_SPEC_COUNT=0" "$(line_for STRICT_SPEC_COUNT)"
run_test "s7_applied" "STRICT_SPEC_STATE=applied" "$(line_for STRICT_SPEC_STATE)"

# Scenario 7a: malformed findings shapes
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s7a_empty_object" "STRICT_SPEC_REASON=strict_pass_failed" "$(line_for STRICT_SPEC_REASON)"

reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","findings":null}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s7a_findings_null" "STRICT_SPEC_REASON=strict_pass_failed" "$(line_for STRICT_SPEC_REASON)"

reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","findings":{"a":1}}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s7a_findings_object" "STRICT_SPEC_REASON=strict_pass_failed" "$(line_for STRICT_SPEC_REASON)"

reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","findings":"nope"}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s7a_findings_string" "STRICT_SPEC_REASON=strict_pass_failed" "$(line_for STRICT_SPEC_REASON)"

reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","findings":[]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s7a_empty_array_applied" "STRICT_SPEC_STATE=applied" "$(line_for STRICT_SPEC_STATE)"
run_test "s7a_empty_array_count0" "STRICT_SPEC_COUNT=0" "$(line_for STRICT_SPEC_COUNT)"

# Scenario 7b: missing mode / ordinary review as strict response
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"findings":[{"check":"ac_consistency","path":"s.md","line":1,"body":"x"}]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s7b_missing_mode" "STRICT_SPEC_REASON=strict_pass_failed" "$(line_for STRICT_SPEC_REASON)"

reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"result":"needs_fixes","findings":[{"severity":"important","message":"blocker"},{"severity":"important","message":"blocker2"}]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s7b_ordinary_as_strict" "STRICT_SPEC_REASON=strict_pass_failed" "$(line_for STRICT_SPEC_REASON)"
run_test "s7b_not_applied_unknown" "no" "$(key_present STRICT_SPEC_UNKNOWN_COUNT)"
run_test "s7b_ordinary_still_clean" "RESULT=clean" "$(line_for RESULT)"

# Scenario 9a: five failure shapes
# 1) non-zero exit
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_RECORD_FILE="$(mktemp)"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_EXIT=1
export MOCK_RECORD_FILE MOCK_ORDINARY_STDOUT MOCK_STRICT_EXIT
run_spec_review
run_test "s9a_nonzero_state" "STRICT_SPEC_STATE=unavailable" "$(line_for STRICT_SPEC_STATE)"
run_test "s9a_nonzero_reason" "STRICT_SPEC_REASON=strict_pass_failed" "$(line_for STRICT_SPEC_REASON)"
run_test "s9a_nonzero_clean" "RESULT=clean" "$(line_for RESULT)"
run_test "s9b_nonzero_invocations" "2" "$(grep -c '^mode=' "$MOCK_RECORD_FILE" || true)"
rm -f "$MOCK_RECORD_FILE"
unset MOCK_STRICT_EXIT

# 2) empty response
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT=''
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s9a_empty_reason" "STRICT_SPEC_REASON=strict_pass_failed" "$(line_for STRICT_SPEC_REASON)"

# 3) unparseable
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='not-json'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s9a_unparseable_reason" "STRICT_SPEC_REASON=strict_pass_failed" "$(line_for STRICT_SPEC_REASON)"

# 4) timeout on strict pass
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_RECORD_FILE="$(mktemp)"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","findings":[]}'
# Make strict sleep past remaining budget: ordinary ~0, timeout 1, strict sleeps 2
LOCAL_AI_REVIEWER_TIMEOUT=1
# Override mock to sleep on strict only
cat > "$MOCK_BIN/local-reviewer-mock" <<'MOCK_REVIEWER'
#!/usr/bin/env bash
mode="${LOCAL_AI_REVIEWER_MODE:-ordinary}"
if [ -n "${MOCK_RECORD_FILE:-}" ]; then
  printf 'mode=%s\n' "$mode" >> "$MOCK_RECORD_FILE"
fi
if [ "$mode" = "strict" ]; then
  sleep 3
  printf '%s\n' '{"mode":"strict_spec_checks","findings":[]}'
  exit 0
fi
printf '%s\n' "${MOCK_ORDINARY_STDOUT}"
exit 0
MOCK_REVIEWER
chmod +x "$MOCK_BIN/local-reviewer-mock"
export MOCK_RECORD_FILE MOCK_ORDINARY_STDOUT LOCAL_AI_REVIEWER_TIMEOUT
START_TS=$(date +%s)
run_spec_review --timeout 2
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))
run_test "s9a_timeout_reason" "STRICT_SPEC_REASON=strict_pass_failed" "$(line_for STRICT_SPEC_REASON)"
run_test "s9a_timeout_clean" "RESULT=clean" "$(line_for RESULT)"
run_test "s9c_within_budget" "yes" "$([ "$ELAPSED" -le 4 ] && echo yes || echo no)"
run_test "s9b_timeout_invocations" "2" "$(grep -c '^mode=' "$MOCK_RECORD_FILE" || true)"
rm -f "$MOCK_RECORD_FILE"
unset LOCAL_AI_REVIEWER_TIMEOUT

# 5) exhausted budget: ordinary consumes whole timeout (date stub advances clock)
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
MOCK_RECORD_FILE="$(mktemp)"
# Stub date so elapsed >= TIMEOUT after the ordinary pass records round_start.
cat > "$MOCK_BIN/date" <<'MOCK_DATE'
#!/usr/bin/env bash
# First call (round start) -> 1000; later calls -> 1000+TIMEOUT
if [ ! -f "${MOCK_DATE_STATE:-/tmp/1650-date-state}" ]; then
  echo 1000 > "${MOCK_DATE_STATE:-/tmp/1650-date-state}"
  echo 1000
  exit 0
fi
echo $((1000 + ${MOCK_DATE_TIMEOUT:-1}))
MOCK_DATE
chmod +x "$MOCK_BIN/date"
MOCK_DATE_STATE="$(mktemp)"
rm -f "$MOCK_DATE_STATE"
MOCK_DATE_TIMEOUT=1
cat > "$MOCK_BIN/local-reviewer-mock" <<'MOCK_REVIEWER'
#!/usr/bin/env bash
mode="${LOCAL_AI_REVIEWER_MODE:-ordinary}"
if [ -n "${MOCK_RECORD_FILE:-}" ]; then
  printf 'mode=%s\n' "$mode" >> "$MOCK_RECORD_FILE"
fi
if [ "$mode" = "ordinary" ]; then
  printf '%s\n' '{"result":"clean","findings":[]}'
  exit 0
fi
printf '%s\n' '{"mode":"strict_spec_checks","findings":[]}'
exit 0
MOCK_REVIEWER
chmod +x "$MOCK_BIN/local-reviewer-mock"
export MOCK_RECORD_FILE MOCK_DATE_STATE MOCK_DATE_TIMEOUT
run_spec_review --timeout 1
run_test "s9a_exhausted_reason" "STRICT_SPEC_REASON=strict_pass_failed" "$(line_for STRICT_SPEC_REASON)"
run_test "s9b_exhausted_invocations" "1" "$(grep -c '^mode=' "$MOCK_RECORD_FILE" || true)"
run_test "s9a_exhausted_clean" "RESULT=clean" "$(line_for RESULT)"
rm -f "$MOCK_RECORD_FILE" "$MOCK_DATE_STATE"
unset MOCK_DATE_STATE MOCK_DATE_TIMEOUT

# Scenario 13: ninth check counted from checklist
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/nine-section.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","findings":[{"check":"ninth_check","path":"s.md","line":1,"body":"n"}]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s13_ninth_counted" "STRICT_SPEC_COUNT=1" "$(line_for STRICT_SPEC_COUNT)"
run_test "s13_ninth_checks" "STRICT_SPEC_CHECKS=ninth_check" "$(line_for STRICT_SPEC_CHECKS)"
run_test "s13_no_unknown" "no" "$(key_present STRICT_SPEC_UNKNOWN_COUNT)"

# Scenario 13a: malformed heading
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/malformed-heading.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","findings":[]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s13a_unreadable" "STRICT_SPEC_REASON=checklist_unreadable" "$(line_for STRICT_SPEC_REASON)"
run_test "s13a_no_count" "no" "$(key_present STRICT_SPEC_COUNT)"

# Scenario 13b: duplicate id
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/duplicate-id.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
export MOCK_ORDINARY_STDOUT
run_spec_review
run_test "s13b_duplicate" "STRICT_SPEC_REASON=checklist_unreadable" "$(line_for STRICT_SPEC_REASON)"

# Scenario 13c: no headings / empty
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/no-headings.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
export MOCK_ORDINARY_STDOUT
run_spec_review
run_test "s13c_no_headings" "STRICT_SPEC_REASON=checklist_unreadable" "$(line_for STRICT_SPEC_REASON)"
run_test "s13c_no_headings_has_result" "RESULT=clean" "$(line_for RESULT)"

reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/empty.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
export MOCK_ORDINARY_STDOUT
run_spec_review
run_test "s13c_empty" "STRICT_SPEC_REASON=checklist_unreadable" "$(line_for STRICT_SPEC_REASON)"
run_test "s13c_empty_has_result" "RESULT=clean" "$(line_for RESULT)"

# Scenario 12 (reviewer-output half): evidence mirrors output
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
LOCAL_AI_REVIEWER_EVIDENCE_FILE="$EVIDENCE_FILE"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT="$THREE_STRICT"
export LOCAL_AI_REVIEWER_EVIDENCE_FILE MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "s12_evidence_has_state" "applied" "$(jq -r '.strict_spec.state' "$EVIDENCE_FILE")"
run_test "s12_evidence_has_count" "3" "$(jq -r '.strict_spec.count' "$EVIDENCE_FILE")"
run_test "s12_evidence_no_reason" "false" "$(jq -r 'if .strict_spec | has("reason") then "true" else "false" end' "$EVIDENCE_FILE")"

reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
LOCAL_AI_REVIEWER_EVIDENCE_FILE="$EVIDENCE_FILE"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_PR_HEAD_BRANCH="feature/test"
MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
export LOCAL_AI_REVIEWER_EVIDENCE_FILE MOCK_ORDINARY_STDOUT MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
export LOCAL_AI_REVIEWER_COMMAND
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
run_test "s12_na_evidence_state" "not_applicable" "$(jq -r '.strict_spec.state' "$EVIDENCE_FILE")"
run_test "s12_na_evidence_no_count" "false" "$(jq -r 'if .strict_spec | has("count") then "true" else "false" end' "$EVIDENCE_FILE")"

# Scenario 11a prompt overrides (codex preset source check)
CODEX_CMD="$REPO_ROOT/scripts/development-workflow/local-codex-review-command.sh"
run_test "s11a_codex_reads_mode" "yes" \
  "$(grep -Fq 'LOCAL_AI_REVIEWER_MODE' "$CODEX_CMD" && echo yes || echo no)"
run_test "s11a_codex_strict_prompt_override" "yes" \
  "$(grep -Fq 'LOCAL_CODEX_REVIEWER_STRICT_PROMPT' "$CODEX_CMD" && echo yes || echo no)"

# ---------------------------------------------------------------------------
# #1653 — stage-specific checklist selection
# ---------------------------------------------------------------------------

source_reviewer_functions() {
  # shellcheck source=scripts/development-workflow/local-ai-reviewer.sh
  HARNESS_MODE=1 source "$REVIEWER"
}

source_reviewer_functions
run_test "1653_s0_sourced_branch_fn" "function" "$(type -t reviewer_stage_for_branch)"
run_test "1653_s0_sourced_policy_fn" "function" "$(type -t reviewer_changed_files_touch_workflow_policy)"
run_test "1653_s0_sourced_resolve_fn" "function" "$(type -t reviewer_resolve_review_stage)"
set +e
HARNESS_MODE=1 "$REVIEWER" >/dev/null 2>&1
_1653_harness_exit=$?
set -e
run_test "1653_s0_direct_harness_exits_2" "2" "$_1653_harness_exit"

run_test "1653_s1_spec" "spec" "$(reviewer_stage_for_branch 'spec/foo')"
run_test "1653_s1_plan" "plan" "$(reviewer_stage_for_branch 'implementation-plan/foo')"
run_test "1653_s1_feature" "implementation" "$(reviewer_stage_for_branch 'feature/foo')"
run_test "1653_s1_refactor" "implementation" "$(reviewer_stage_for_branch 'refactor/foo')"
run_test "1653_s1_fix" "implementation" "$(reviewer_stage_for_branch 'fix/foo')"
run_test "1653_s1_hotfix" "implementation" "$(reviewer_stage_for_branch 'hotfix/foo')"

run_test "1653_s2_empty" "default" "$(reviewer_stage_for_branch '')"
run_test "1653_s2_main" "default" "$(reviewer_stage_for_branch 'main')"
run_test "1653_s2_develop" "default" "$(reviewer_stage_for_branch 'develop')"
run_test "1653_s2_integration" "default" "$(reviewer_stage_for_branch 'develop-internal-reviewer-effectiveness')"
run_test "1653_s2_specification" "default" "$(reviewer_stage_for_branch 'specification/foo')"

_1653_policy_ok() {
  printf '%s\n' "$1" | reviewer_changed_files_touch_workflow_policy >/dev/null
}
run_test "1653_s3_review_md" "yes" "$(_1653_policy_ok 'REVIEW.md' && echo yes || echo no)"
run_test "1653_s3_agents_md" "yes" "$(_1653_policy_ok 'AGENTS.md' && echo yes || echo no)"
run_test "1653_s3_claude_md" "yes" "$(_1653_policy_ok 'CLAUDE.md' && echo yes || echo no)"
run_test "1653_s3_gemini_md" "yes" "$(_1653_policy_ok 'GEMINI.md' && echo yes || echo no)"
run_test "1653_s3_llm_rules_md" "yes" "$(_1653_policy_ok 'LLM_RULES.md' && echo yes || echo no)"
run_test "1653_s3_workflow_yaml" "yes" "$(_1653_policy_ok '.ai-dev-workflow.yaml' && echo yes || echo no)"
run_test "1653_s3_docs_workflow" "yes" "$(_1653_policy_ok 'docs/workflow/foo.md' && echo yes || echo no)"
run_test "1653_s3_docs_best_practices" "yes" "$(_1653_policy_ok 'docs/best-practices/1-general.md' && echo yes || echo no)"
run_test "1653_s3_scripts_dev_workflow" "yes" "$(_1653_policy_ok 'scripts/development-workflow/local-ai-reviewer.sh' && echo yes || echo no)"
run_test "1653_s3_claude_agents" "yes" "$(_1653_policy_ok '.claude/agents/code-reviewer.md' && echo yes || echo no)"
run_test "1653_s3_cursor_agents" "yes" "$(_1653_policy_ok '.cursor/agents/code-reviewer.md' && echo yes || echo no)"
run_test "1653_s3_codex_skills" "yes" "$(_1653_policy_ok '.codex/skills/workflow-code-reviewer/SKILL.md' && echo yes || echo no)"
run_test "1653_s3_agents_skills" "yes" "$(_1653_policy_ok '.agents/skills/x/SKILL.md' && echo yes || echo no)"

run_test "1653_s3_neg_spec" "no" "$(_1653_policy_ok 'docs/specs/developments/x/1_x_specs.md' && echo yes || echo no)"
run_test "1653_s3_neg_project" "no" "$(_1653_policy_ok 'docs/project/1-business-domain.md' && echo yes || echo no)"
run_test "1653_s3_neg_ci" "no" "$(_1653_policy_ok '.github/workflows/ci.yml' && echo yes || echo no)"
run_test "1653_s3_neg_src" "no" "$(_1653_policy_ok 'src/app/main.ts' && echo yes || echo no)"

run_test "1653_s4_mixed_yes" "yes" "$(printf 'src/app/main.ts\nREVIEW.md\n' | reviewer_changed_files_touch_workflow_policy >/dev/null && echo yes || echo no)"
run_test "1653_s4_none_no" "no" "$(printf 'src/app/main.ts\ndocs/project/x.md\n' | reviewer_changed_files_touch_workflow_policy >/dev/null && echo yes || echo no)"
run_test "1653_s5_empty_no" "no" "$(printf '' | reviewer_changed_files_touch_workflow_policy >/dev/null && echo yes || echo no)"

_1653_parse_resolve() {
  local branch="$1" json="$2"
  reviewer_resolve_review_stage "$branch" "$json"
}

_1653_s5a_out="$(_1653_parse_resolve 'refactor/foo' '["REVIEW.md","src/app/main.ts"]')"
run_test "1653_s5a_stage" "implementation" "$(printf '%s\n' "$_1653_s5a_out" | sed -n '1p')"
run_test "1653_s5a_source" "branch+files" "$(printf '%s\n' "$_1653_s5a_out" | sed -n '2p')"
run_test "1653_s5a_lists" "Code Review Checklist,Workflow Policy Review Checklist" "$(printf '%s\n' "$_1653_s5a_out" | sed -n '3p')"

_1653_s5a_empty="$(_1653_parse_resolve 'refactor/foo' '[]')"
run_test "1653_s5a_empty_source" "branch" "$(printf '%s\n' "$_1653_s5a_empty" | sed -n '2p')"
run_test "1653_s5a_empty_no_policy" "Code Review Checklist" "$(printf '%s\n' "$_1653_s5a_empty" | sed -n '3p')"

_1653_s5a_blank="$(_1653_parse_resolve 'refactor/foo' '""')"
run_test "1653_s5a_blank_source" "branch" "$(printf '%s\n' "$_1653_s5a_blank" | sed -n '2p')"
run_test "1653_s5a_blank_no_policy" "Code Review Checklist" "$(printf '%s\n' "$_1653_s5a_blank" | sed -n '3p')"

_1653_pipe_max=2097152
if [ -r /proc/sys/fs/pipe-max-size ]; then
  _1653_pipe_max="$(cat /proc/sys/fs/pipe-max-size)"
fi
_1653_target=$((_1653_pipe_max * 2))
if [ "$_1653_target" -lt 2097152 ]; then
  _1653_target=2097152
fi
_1653_paths=(REVIEW.md)
_1653_i=0
_1653_chunk=500
while [ "$(printf '%s\n' "${_1653_paths[@]}" | wc -c | tr -d ' ')" -le "$_1653_target" ]; do
  for ((j=0; j<_1653_chunk; j++)); do
    _1653_paths+=("docs/specs/developments/filler-$(printf '%05d' "$((_1653_i + j))")/1_x.md")
  done
  _1653_i=$((_1653_i + _1653_chunk))
  _1653_chunk=$((_1653_chunk * 2))
done
_1653_big_json="$(printf '%s\n' "${_1653_paths[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))')"
_1653_s5b_out="$(_1653_parse_resolve 'refactor/foo' "$_1653_big_json")"
run_test "1653_s5b_policy_added" "branch+files" "$(printf '%s\n' "$_1653_s5b_out" | sed -n '2p')"

_1653_merge_case() {
  local branch="$1" json="$2" exp_stage="$3" exp_source="$4" exp_lists="$5"
  local out stage source lists
  out="$(reviewer_resolve_review_stage "$branch" "$json")"
  stage="$(printf '%s\n' "$out" | sed -n '1p')"
  source="$(printf '%s\n' "$out" | sed -n '2p')"
  lists="$(printf '%s\n' "$out" | sed -n '3p')"
  run_test "1653_s6_${branch//\//_}_stage" "$exp_stage" "$stage"
  run_test "1653_s6_${branch//\//_}_source" "$exp_source" "$source"
  run_test "1653_s6_${branch//\//_}_lists" "$exp_lists" "$lists"
}

_1653_merge_case 'spec/foo' '["src/app/main.ts"]' 'spec' 'branch' 'Spec Review Checklist'
_1653_merge_case 'spec/foo' '["REVIEW.md"]' 'spec' 'branch+files' 'Spec Review Checklist,Workflow Policy Review Checklist'
_1653_merge_case 'implementation-plan/foo' '["src/app/main.ts"]' 'plan' 'branch' 'Plan Review Checklist'
_1653_merge_case 'implementation-plan/foo' '["REVIEW.md"]' 'plan' 'branch+files' 'Plan Review Checklist,Workflow Policy Review Checklist'
_1653_merge_case 'refactor/foo' '["src/app/main.ts"]' 'implementation' 'branch' 'Code Review Checklist'
_1653_merge_case 'refactor/foo' '["REVIEW.md"]' 'implementation' 'branch+files' 'Code Review Checklist,Workflow Policy Review Checklist'
_1653_merge_case 'main' '["src/app/main.ts"]' 'default' 'none' ''
_1653_merge_case 'main' '["REVIEW.md"]' 'default' 'none' ''

for _1653_heading in \
  'Spec Review Checklist' \
  'Plan Review Checklist' \
  'Code Review Checklist' \
  'Workflow Policy Review Checklist'; do
  run_test "1653_s9_heading_${_1653_heading// /_}" "yes" \
    "$(grep -Fq "## ${_1653_heading}" "$REPO_ROOT/REVIEW.md" && echo yes || echo no)"
done

reset_mocks
BUNDLE_DUMP="$(mktemp)"
cat > "$MOCK_BIN/local-reviewer-mock" <<'MOCK_REVIEWER'
#!/usr/bin/env bash
if [ -n "${MOCK_BUNDLE_DUMP:-}" ]; then
  cp "$CONTEXT_BUNDLE_PATH" "$MOCK_BUNDLE_DUMP"
fi
printf '%s\n' '{"result":"clean","findings":[]}'
MOCK_REVIEWER
chmod +x "$MOCK_BIN/local-reviewer-mock"
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
MOCK_BUNDLE_DUMP="$BUNDLE_DUMP"
MOCK_PR_HEAD_BRANCH="refactor/1653-split-reviewer-prompts-by-stage"
MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
export LOCAL_AI_REVIEWER_COMMAND MOCK_BUNDLE_DUMP MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
run_test "1653_s12_bundle_stage" "implementation" "$(jq -r '.review_stage' "$BUNDLE_DUMP")"
run_test "1653_s12_bundle_source" "branch+files" "$(jq -r '.review_stage_source' "$BUNDLE_DUMP")"
run_test "1653_s12_bundle_schema" "local_ai_reviewer_context.v1" "$(jq -r '.schema_version' "$BUNDLE_DUMP")"
for _1653_field in schema_version pr_number owner repo base_branch head_branch reviewed_head changed_files pr_body diff_name_status diff_stat review_contract graph_context review_stage review_stage_source review_checklists; do
  run_test "1653_s12_field_${_1653_field}" "yes" "$(jq -e "has(\"${_1653_field}\")" "$BUNDLE_DUMP" >/dev/null && echo yes || echo no)"
done
run_test "1653_out_review_stage" "REVIEW_STAGE=implementation" "$(line_for REVIEW_STAGE)"
run_test "1653_out_review_source" "REVIEW_STAGE_SOURCE=branch+files" "$(line_for REVIEW_STAGE_SOURCE)"
run_test "1653_out_review_lists" "REVIEW_CHECKLISTS=Code Review Checklist,Workflow Policy Review Checklist" "$(line_for REVIEW_CHECKLISTS)"
rm -f "$BUNDLE_DUMP"

reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
LOCAL_AI_REVIEWER_EVIDENCE_FILE="$EVIDENCE_FILE"
MOCK_PR_HEAD_BRANCH="refactor/1653-split-reviewer-prompts-by-stage"
MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
set_mock_stdout '{"result":"clean","findings":[]}'
export LOCAL_AI_REVIEWER_COMMAND LOCAL_AI_REVIEWER_EVIDENCE_FILE MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA MOCK_LOCAL_REVIEWER_STDOUT
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
run_test "1653_s14_evidence_stage" "implementation" "$(jq -r '.review_stage.stage' "$EVIDENCE_FILE")"
run_test "1653_s14_evidence_source" "branch+files" "$(jq -r '.review_stage.source' "$EVIDENCE_FILE")"
run_test "1653_s14_evidence_schema" "local_ai_reviewer_evidence.v1" "$(jq -r '.schema_version' "$EVIDENCE_FILE")"

# ---------------------------------------------------------------------------
# #1654 — review doctrine supply
# ---------------------------------------------------------------------------

_1654_doctrine_root="$(mktemp -d)"
_1654_install_doctrine() {
  local root="$1"
  local src="$2"
  mkdir -p "$root/docs/workflow/development-workflow"
  cp "$src" "$root/docs/workflow/development-workflow/review-doctrine.md"
}

_1654_run_supply() {
  local root="$1"
  (cd "$root" && reviewer_doctrine_supply)
}

_1654_independent_version() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print substr($1,1,12)}'
  else
    shasum -a 256 "$file" | awk '{print substr($1,1,12)}'
  fi
}

# Scenario 1: four states, all four values
_1654_install_doctrine "$_1654_doctrine_root" "$REPO_ROOT/docs/workflow/development-workflow/review-doctrine.md"
_1654_supplied="$(_1654_run_supply "$_1654_doctrine_root")"
run_test "1654_s1_supplied_state" "supplied" "$(printf '%s\n' "$_1654_supplied" | jq -r '.state')"
run_test "1654_s1_supplied_count" "5" "$(printf '%s\n' "$_1654_supplied" | jq -r '.pattern_count')"
run_test "1654_s1_supplied_version_len" "12" "$(printf '%s\n' "$_1654_supplied" | jq -r '.version | length')"
run_test "1654_s1_supplied_text_nonempty" "true" "$(printf '%s\n' "$_1654_supplied" | jq -r '.text | length > 0')"

_1654_absent_root="$(mktemp -d)"
_1654_absent="$(_1654_run_supply "$_1654_absent_root")"
run_test "1654_s1_absent_state" "absent" "$(printf '%s\n' "$_1654_absent" | jq -r '.state')"
run_test "1654_s1_absent_count" "0" "$(printf '%s\n' "$_1654_absent" | jq -r '.pattern_count')"
run_test "1654_s1_absent_version" "" "$(printf '%s\n' "$_1654_absent" | jq -r '.version')"

_1654_unreadable_root="$(mktemp -d)"
mkdir -p "$_1654_unreadable_root/docs/workflow/development-workflow"
printf 'secret\n' > "$_1654_unreadable_root/docs/workflow/development-workflow/review-doctrine.md"
chmod 000 "$_1654_unreadable_root/docs/workflow/development-workflow/review-doctrine.md"
_1654_unreadable="$(_1654_run_supply "$_1654_unreadable_root")"
chmod 644 "$_1654_unreadable_root/docs/workflow/development-workflow/review-doctrine.md"
run_test "1654_s1_unreadable_state" "unreadable" "$(printf '%s\n' "$_1654_unreadable" | jq -r '.state')"

# Scenario 1a: grep exit >1 is unreadable (distinct from exit 1 → count 0 supplied)
_1654_grep_err_bin="$(mktemp -d)"
cat > "$_1654_grep_err_bin/grep" <<'GREP_STUB'
#!/usr/bin/env bash
if [[ "$*" == *'-c '^###\ '* ]]; then exit 2; fi
exec /usr/bin/grep "$@"
GREP_STUB
chmod +x "$_1654_grep_err_bin/grep"
_1654_grep_err_root="$(mktemp -d)"
_1654_install_doctrine "$_1654_grep_err_root" "$REPO_ROOT/docs/workflow/development-workflow/review-doctrine.md"
_1654_grep_err_out="$(cd "$_1654_grep_err_root" && PATH="$_1654_grep_err_bin:$PATH" reviewer_doctrine_supply)"
run_test "1654_s1a_grep_error_unreadable" "unreadable" "$(printf '%s\n' "$_1654_grep_err_out" | jq -r '.state')"

# Scenario 1a: cp failure while catalogue present → unreadable
_1654_cp_fail_bin="$(mktemp -d)"
cat > "$_1654_cp_fail_bin/cp" <<'CP_STUB'
#!/usr/bin/env bash
if [[ "$1" == *review-doctrine.md ]]; then exit 1; fi
exec /bin/cp "$@"
CP_STUB
chmod +x "$_1654_cp_fail_bin/cp"
_1654_cp_fail_root="$(mktemp -d)"
_1654_install_doctrine "$_1654_cp_fail_root" "$REPO_ROOT/docs/workflow/development-workflow/review-doctrine.md"
_1654_cp_fail_out="$(cd "$_1654_cp_fail_root" && PATH="$_1654_cp_fail_bin:/usr/bin:/bin" reviewer_doctrine_supply)"
run_test "1654_s1a_cp_fail_unreadable" "unreadable" "$(printf '%s\n' "$_1654_cp_fail_out" | jq -r '.state')"

# Scenario 1b: returned version is hash of returned text (same snapshot)
_1654_text_hash="$(printf '%s\n' "$_1654_supplied" | jq -j -r '.text' | if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print substr($1,1,12)}')"
run_test "1654_s1b_version_matches_text" "$_1654_text_hash" "$(printf '%s\n' "$_1654_supplied" | jq -r '.version')"

# Scenario 6: no digest command → unreadable, not supplied with empty version
_1654_no_digest_root="$(mktemp -d)"
_1654_install_doctrine "$_1654_no_digest_root" "$REPO_ROOT/docs/workflow/development-workflow/review-doctrine.md"
_1654_no_digest_path="$(mktemp -d)"
for _1654_tool in awk bash cat cp date dirname grep jq mktemp perl rm sed sh sleep tr wc; do
  _1654_p="$(command -v "$_1654_tool" 2>/dev/null || true)"
  [ -n "$_1654_p" ] && ln -sf "$_1654_p" "$_1654_no_digest_path/$_1654_tool"
done
_1654_no_digest_out="$(cd "$_1654_no_digest_root" && PATH="$_1654_no_digest_path" reviewer_doctrine_supply)"
run_test "1654_s6_no_digest_state" "unreadable" "$(printf '%s\n' "$_1654_no_digest_out" | jq -r '.state')"
run_test "1654_s6_no_digest_version_empty" "" "$(printf '%s\n' "$_1654_no_digest_out" | jq -r '.version')"

_1654_oversized_root="$(mktemp -d)"
_1654_oversized_file="$_1654_oversized_root/docs/workflow/development-workflow/review-doctrine.md"
mkdir -p "$(dirname "$_1654_oversized_file")"
python3 - <<'PY' "$REPO_ROOT/docs/workflow/development-workflow/review-doctrine.md" "$_1654_oversized_file"
import pathlib, sys
body = pathlib.Path(sys.argv[1]).read_bytes()
while len(body) <= 12000:
    body += b"x"
pathlib.Path(sys.argv[2]).write_bytes(body[:12001])
PY
_1654_oversized="$(_1654_run_supply "$_1654_oversized_root")"
run_test "1654_s2_oversized_state" "oversized" "$(printf '%s\n' "$_1654_oversized" | jq -r '.state')"
run_test "1654_s2_oversized_text_empty" "" "$(printf '%s\n' "$_1654_oversized" | jq -r '.text')"
run_test "1654_s2_oversized_version_present" "true" "$(printf '%s\n' "$_1654_oversized" | jq -r '.version | length > 0')"

# Scenario 4: empty catalogue
_1654_empty_root="$(mktemp -d)"
_1654_install_doctrine "$_1654_empty_root" "$REPO_ROOT/scripts/development-workflow/tests/fixtures/review-doctrine/empty.md"
_1654_empty="$(_1654_run_supply "$_1654_empty_root")"
run_test "1654_s4_empty_supplied" "supplied" "$(printf '%s\n' "$_1654_empty" | jq -r '.state')"
run_test "1654_s4_empty_count" "0" "$(printf '%s\n' "$_1654_empty" | jq -r '.pattern_count')"

# Scenario 5: version hash
_1654_expected_version="$(_1654_independent_version "$REPO_ROOT/docs/workflow/development-workflow/review-doctrine.md")"
run_test "1654_s5_version_matches_file" "$_1654_expected_version" "$(printf '%s\n' "$_1654_supplied" | jq -r '.version')"

# Scenario 7/7a: bundle fields and byte-identical text
reset_mocks
BUNDLE_DUMP="$(mktemp)"
cat > "$MOCK_BIN/local-reviewer-mock" <<'MOCK_REVIEWER'
#!/usr/bin/env bash
if [ -n "${MOCK_BUNDLE_DUMP:-}" ]; then
  cp "$CONTEXT_BUNDLE_PATH" "$MOCK_BUNDLE_DUMP"
fi
printf '%s\n' '{"result":"clean","findings":[]}'
MOCK_REVIEWER
chmod +x "$MOCK_BIN/local-reviewer-mock"
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
MOCK_BUNDLE_DUMP="$BUNDLE_DUMP"
MOCK_PR_HEAD_BRANCH="feature/1654-codex-patterns-to-local-doctrine"
MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
export LOCAL_AI_REVIEWER_COMMAND MOCK_BUNDLE_DUMP MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
_1654_install_doctrine "$VALID_REPO_ROOT" "$REPO_ROOT/docs/workflow/development-workflow/review-doctrine.md"
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
for _1654_field in schema_version pr_number owner repo base_branch head_branch reviewed_head changed_files pr_body diff_name_status diff_stat review_contract graph_context review_stage review_stage_source review_checklists review_doctrine review_doctrine_state review_doctrine_pattern_count review_doctrine_version; do
  run_test "1654_s7_field_${_1654_field}" "yes" "$(jq -e "has(\"${_1654_field}\")" "$BUNDLE_DUMP" >/dev/null && echo yes || echo no)"
done
run_test "1654_s7a_bytes_match" "0" "$(jq -j -r '.review_doctrine' "$BUNDLE_DUMP" > /tmp/1654-doctrine-bytes.tmp && cmp -s "$VALID_REPO_ROOT/docs/workflow/development-workflow/review-doctrine.md" /tmp/1654-doctrine-bytes.tmp && echo 0 || echo 1)"
run_test "1654_s8_state_kv" "REVIEW_DOCTRINE_STATE=supplied" "$(line_for REVIEW_DOCTRINE_STATE)"
run_test "1654_s8_count_kv" "REVIEW_DOCTRINE_PATTERN_COUNT=5" "$(line_for REVIEW_DOCTRINE_PATTERN_COUNT)"
run_test "1654_s8_no_text_kv" "0" "$(grep -c '^REVIEW_DOCTRINE=' "$OUTPUT_FILE" 2>/dev/null || true)"
_1654_emit_out="$(bash -c 'HARNESS_MODE=1 source "$1"; emit_prefixed_platform_output 1 "$(cat "$2")"' bash "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" "$OUTPUT_FILE")"
run_test "1654_s8_platform_state" "1" "$(printf '%s\n' "$_1654_emit_out" | grep -c '^PLATFORM_1_REVIEW_DOCTRINE_STATE=' || true)"
run_test "1654_s8_platform_count" "1" "$(printf '%s\n' "$_1654_emit_out" | grep -c '^PLATFORM_1_REVIEW_DOCTRINE_PATTERN_COUNT=' || true)"
run_test "1654_s8_platform_version" "1" "$(printf '%s\n' "$_1654_emit_out" | grep -c '^PLATFORM_1_REVIEW_DOCTRINE_VERSION=' || true)"
run_test "1654_s8_no_fabricated" "0" "$(printf '%s\n' "$_1654_emit_out" | grep -c '^PLATFORM_1_[^=]*Shape' || true)"
_1654_absent_kv="$(printf '%s\n' 'RESULT=clean' 'REVIEW_DOCTRINE_STATE=absent' 'REVIEW_DOCTRINE_PATTERN_COUNT=0' 'REVIEW_DOCTRINE_VERSION=')"
_1654_absent_emit="$(bash -c 'HARNESS_MODE=1 source "$1"; emit_local_ai_review_doctrine_keys "$2"' bash "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" "$_1654_absent_kv")"
run_test "1654_s8_absent_forwards_version" "REVIEW_DOCTRINE_VERSION=" "$(printf '%s\n' "$_1654_absent_emit" | grep '^REVIEW_DOCTRINE_VERSION=' || true)"
run_test "1654_s8_absent_forwards_count" "REVIEW_DOCTRINE_PATTERN_COUNT=0" "$(printf '%s\n' "$_1654_absent_emit" | grep '^REVIEW_DOCTRINE_PATTERN_COUNT=' || true)"
rm -f "$BUNDLE_DUMP"

# Scenario 8a: evidence object
reset_mocks
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
LOCAL_AI_REVIEWER_EVIDENCE_FILE="$EVIDENCE_FILE"
MOCK_PR_HEAD_BRANCH="feature/1654-codex-patterns-to-local-doctrine"
MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
set_mock_stdout '{"result":"clean","findings":[]}'
export LOCAL_AI_REVIEWER_COMMAND LOCAL_AI_REVIEWER_EVIDENCE_FILE MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA MOCK_LOCAL_REVIEWER_STDOUT
_1654_install_doctrine "$VALID_REPO_ROOT" "$REPO_ROOT/docs/workflow/development-workflow/review-doctrine.md"
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
run_test "1654_s8a_evidence_state" "supplied" "$(jq -r '.review_doctrine.state' "$EVIDENCE_FILE")"
run_test "1654_s8a_evidence_count_type" "number" "$(jq -r '.review_doctrine.pattern_count | type' "$EVIDENCE_FILE")"
run_test "1654_s8a_evidence_version_type" "string" "$(jq -r '.review_doctrine.version | type' "$EVIDENCE_FILE")"

# Scenario 9: every stage gets doctrine
for _1654_branch in spec/foo implementation-plan/foo feature/foo refactor/foo fix/foo hotfix/foo main develop; do
  reset_mocks
  BUNDLE_DUMP="$(mktemp)"
  cat > "$MOCK_BIN/local-reviewer-mock" <<'MOCK_REVIEWER'
#!/usr/bin/env bash
cp "$CONTEXT_BUNDLE_PATH" "$MOCK_BUNDLE_DUMP"
printf '%s\n' '{"result":"clean","findings":[]}'
MOCK_REVIEWER
  chmod +x "$MOCK_BIN/local-reviewer-mock"
  LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
  MOCK_BUNDLE_DUMP="$BUNDLE_DUMP"
  MOCK_PR_HEAD_BRANCH="$_1654_branch"
  MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
  export LOCAL_AI_REVIEWER_COMMAND MOCK_BUNDLE_DUMP MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
  _1654_install_doctrine "$VALID_REPO_ROOT" "$REPO_ROOT/docs/workflow/development-workflow/review-doctrine.md"
  run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
  run_test "1654_s9_${_1654_branch//\//_}_state" "supplied" "$(jq -r '.review_doctrine_state' "$BUNDLE_DUMP")"
  rm -f "$BUNDLE_DUMP"
done

rm -rf "$_1654_doctrine_root" "$_1654_absent_root" "$_1654_unreadable_root" "$_1654_oversized_root" "$_1654_empty_root" "$_1654_grep_err_bin" "$_1654_grep_err_root" "$_1654_cp_fail_bin" "$_1654_cp_fail_root" "$_1654_no_digest_root" "$_1654_no_digest_path"

# ---------------------------------------------------------------------------
# Strict plan contract checks (#1655) — scenarios 1, 7, 13, 15
# ---------------------------------------------------------------------------

PLAN_CHECKLIST_FIXTURES="$FIXTURES/strict-plan-checks"
SHIPPED_PLAN_CHECKLIST="$REPO_ROOT/docs/workflow/development-workflow/strict-plan-checks.md"
PLAN_DEV_DIR="docs/specs/developments/20260831062000_1655-strict-plan-review-mode"
PLAN_DOC="$PLAN_DEV_DIR/2_1655-strict-plan-review-mode_implementation-plan.md"
PLAN_SPEC="$PLAN_DEV_DIR/1_1655-strict-plan-review-mode_specs.md"

install_plan_checklist_into_repo() {
  local src="$1"
  mkdir -p "$VALID_REPO_ROOT/docs/workflow/development-workflow"
  cp "$src" "$VALID_REPO_ROOT/docs/workflow/development-workflow/strict-plan-checks.md"
  git -C "$VALID_REPO_ROOT" add docs/workflow/development-workflow/strict-plan-checks.md >/dev/null 2>&1 || true # workflow-shell-guard: allow SH001
}

install_plan_artifacts() {
  local with_spec="${1:-1}"
  mkdir -p "$VALID_REPO_ROOT/$PLAN_DEV_DIR"
  cp "$REPO_ROOT/$PLAN_DOC" "$VALID_REPO_ROOT/$PLAN_DOC" 2>/dev/null || \
    printf '# Plan\n\n**Spec**: [spec](./1_1655-strict-plan-review-mode_specs.md)\n' > "$VALID_REPO_ROOT/$PLAN_DOC"
  if [ "$with_spec" = "1" ]; then
    cp "$REPO_ROOT/$PLAN_SPEC" "$VALID_REPO_ROOT/$PLAN_SPEC" 2>/dev/null || \
      printf '# Spec\n\n- [ ] AC-1. Example\n' > "$VALID_REPO_ROOT/$PLAN_SPEC"
    git -C "$VALID_REPO_ROOT" add "$PLAN_DOC" "$PLAN_SPEC" >/dev/null 2>&1 || true # workflow-shell-guard: allow SH001
  else
    rm -f "$VALID_REPO_ROOT/$PLAN_SPEC"
    git -C "$VALID_REPO_ROOT" rm -f "$PLAN_SPEC" >/dev/null 2>&1 || true # workflow-shell-guard: allow SH001
    git -C "$VALID_REPO_ROOT" add "$PLAN_DOC" >/dev/null 2>&1 || true # workflow-shell-guard: allow SH001
  fi
  git -C "$VALID_REPO_ROOT" commit -m "test: plan artifacts" >/dev/null 2>&1 || true # workflow-shell-guard: allow SH001
}

install_plan_gh_mock() {
  local changed_path="$1"
  local head_branch="${MOCK_PR_HEAD_BRANCH:-implementation-plan/1655-test}"
  cat > "$MOCK_BIN/gh" <<MOCK_GH
#!/usr/bin/env bash
case "\$*" in
  *"pr view 123"*"--json baseRefName,headRefName,headRefOid"*)
    printf '{"baseRefName":"develop","headRefName":"$head_branch","headRefOid":"%s"}\n' "\${MOCK_PR_HEAD_SHA}"
    exit 0
    ;;
  *"pr diff 123"*"--name-only"*)
    printf '%s\nREVIEW.md\n' "$changed_path"
    exit 0
    ;;
  *) exit 1 ;;
esac
MOCK_GH
  chmod +x "$MOCK_BIN/gh"
}

run_plan_review() {
  MOCK_PR_HEAD_BRANCH="${MOCK_PR_HEAD_BRANCH:-implementation-plan/1655-test}"
  MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
  export MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
  LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
  export LOCAL_AI_REVIEWER_COMMAND
  run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
}

# Scenario 15: spec stage — spec applied, plan not_applicable stage_not_plan
reset_mocks
install_recording_two_pass_mock
install_checklist_into_repo "$CHECKLIST_FIXTURES/well-formed.md"
install_plan_checklist_into_repo "$PLAN_CHECKLIST_FIXTURES/well-formed.md"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_spec_checks","findings":[]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
run_spec_review
run_test "1655_s15_spec_applied" "STRICT_SPEC_STATE=applied" "$(line_for STRICT_SPEC_STATE)"
run_test "1655_s15_plan_na" "STRICT_PLAN_STATE=not_applicable" "$(line_for STRICT_PLAN_STATE)"
run_test "1655_s15_plan_reason" "STRICT_PLAN_REASON=stage_not_plan" "$(line_for STRICT_PLAN_REASON)"

# Scenario 7: partial applied set without source spec (fresh repo — no spec at HEAD)
PLAN_REPO="$(mktemp -d)"
git -C "$PLAN_REPO" init -q
git -C "$PLAN_REPO" config user.email "test@example.com"
git -C "$PLAN_REPO" config user.name "Test User"
printf '# Review\n' > "$PLAN_REPO/REVIEW.md"
git -C "$PLAN_REPO" add REVIEW.md
git -C "$PLAN_REPO" commit -q -m "fixture"
git -C "$PLAN_REPO" remote add origin "git@github.com:owner/repo.git"
mkdir -p "$PLAN_REPO/$PLAN_DEV_DIR"
printf '# Plan\n' > "$PLAN_REPO/$PLAN_DOC"
git -C "$PLAN_REPO" add "$PLAN_DOC"
git -C "$PLAN_REPO" commit -q -m "plan-only"
mkdir -p "$PLAN_REPO/docs/workflow/development-workflow"
cp "$PLAN_CHECKLIST_FIXTURES/well-formed.md" "$PLAN_REPO/docs/workflow/development-workflow/strict-plan-checks.md"
reset_mocks
install_recording_two_pass_mock
install_plan_gh_mock "$PLAN_DOC"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_plan_checks","findings":[]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
MOCK_PR_HEAD_BRANCH="implementation-plan/1655-no-spec"
MOCK_PR_HEAD_SHA="$(git -C "$PLAN_REPO" rev-parse HEAD)"
export MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
export LOCAL_AI_REVIEWER_COMMAND
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$PLAN_REPO"
run_test "1655_s7_partial_applied" "STRICT_PLAN_APPLIED=source_declaration,phase_ordering,dependency_state,reversal_risk" "$(line_for STRICT_PLAN_APPLIED)"
rm -rf "$PLAN_REPO"

# Scenario 17: mixed plans — source-dependent finding on no-spec plan is dropped
PLAN_REPO="$(mktemp -d)"
PLAN_DEV_A="docs/specs/developments/20260831062000_1655-strict-plan-review-mode"
PLAN_DEV_B="docs/specs/developments/20260831062001_1655-other"
PLAN_DOC_A="$PLAN_DEV_A/2_1655-strict-plan-review-mode_implementation-plan.md"
PLAN_SPEC_A="$PLAN_DEV_A/1_1655-strict-plan-review-mode_specs.md"
PLAN_DOC_B="$PLAN_DEV_B/2_1655-other_implementation-plan.md"
git -C "$PLAN_REPO" init -q
git -C "$PLAN_REPO" config user.email "test@example.com"
git -C "$PLAN_REPO" config user.name "Test User"
printf '# Review\n' > "$PLAN_REPO/REVIEW.md"
git -C "$PLAN_REPO" add REVIEW.md
git -C "$PLAN_REPO" commit -q -m "fixture"
git -C "$PLAN_REPO" remote add origin "git@github.com:owner/repo.git"
mkdir -p "$PLAN_REPO/$PLAN_DEV_A" "$PLAN_REPO/$PLAN_DEV_B"
printf '# Plan A\n' > "$PLAN_REPO/$PLAN_DOC_A"
printf '# Spec A\n' > "$PLAN_REPO/$PLAN_SPEC_A"
printf '# Plan B\n' > "$PLAN_REPO/$PLAN_DOC_B"
git -C "$PLAN_REPO" add "$PLAN_DOC_A" "$PLAN_SPEC_A" "$PLAN_DOC_B"
git -C "$PLAN_REPO" commit -q -m "mixed plans"
mkdir -p "$PLAN_REPO/docs/workflow/development-workflow"
cp "$PLAN_CHECKLIST_FIXTURES/well-formed.md" "$PLAN_REPO/docs/workflow/development-workflow/strict-plan-checks.md"
reset_mocks
install_recording_two_pass_mock
cat > "$MOCK_BIN/gh" <<MOCK_GH
#!/usr/bin/env bash
case "\$*" in
  *"pr view 123"*"--json baseRefName,headRefName,headRefOid"*)
    printf '{"baseRefName":"develop","headRefName":"implementation-plan/1655-mixed","headRefOid":"%s"}\n' "\${MOCK_PR_HEAD_SHA}"
    exit 0
    ;;
  *"pr diff 123"*"--name-only"*)
    printf '%s\n%s\nREVIEW.md\n' "$PLAN_DOC_A" "$PLAN_DOC_B"
    exit 0
    ;;
  *) exit 1 ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_plan_checks","findings":[{"check":"unspecified_step","path":"'"$PLAN_DOC_B"'","line":1,"body":"should drop"},{"check":"phase_ordering","path":"'"$PLAN_DOC_B"'","line":2,"body":"should keep"}]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
MOCK_PR_HEAD_BRANCH="implementation-plan/1655-mixed"
MOCK_PR_HEAD_SHA="$(git -C "$PLAN_REPO" rev-parse HEAD)"
export MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
export LOCAL_AI_REVIEWER_COMMAND
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$PLAN_REPO"
run_test "1655_s17_applied_all7" "STRICT_PLAN_APPLIED=source_declaration,unspecified_step,spec_traceability,ac_test_coverage,phase_ordering,dependency_state,reversal_risk" "$(line_for STRICT_PLAN_APPLIED)"
run_test "1655_s17_drop_source_on_nospec" "STRICT_PLAN_COUNT=1" "$(line_for STRICT_PLAN_COUNT)"
run_test "1655_s17_kept_phase_ordering" "STRICT_PLAN_CHECKS=phase_ordering" "$(line_for STRICT_PLAN_CHECKS)"
run_test "1655_s17_unknown_from_drop" "STRICT_PLAN_UNKNOWN_COUNT=1" "$(line_for STRICT_PLAN_UNKNOWN_COUNT)"
run_test "1655_s17_unknown_detail" "STRICT_1_CHECK=unknown" "$(line_for STRICT_1_CHECK)"
rm -rf "$PLAN_REPO"

# Scenario 7a: coverage follows spec presence, not plan declaration
PLAN_REPO="$(mktemp -d)"
git -C "$PLAN_REPO" init -q
git -C "$PLAN_REPO" config user.email "test@example.com"
git -C "$PLAN_REPO" config user.name "Test User"
printf '# Review\n' > "$PLAN_REPO/REVIEW.md"
git -C "$PLAN_REPO" add REVIEW.md
git -C "$PLAN_REPO" commit -q -m "fixture"
git -C "$PLAN_REPO" remote add origin "git@github.com:owner/repo.git"
mkdir -p "$PLAN_REPO/$PLAN_DEV_DIR"
printf '# Plan\n\n**Source of truth**: None — Refactor item.\n' > "$PLAN_REPO/$PLAN_DOC"
printf '# Spec\n\n- [ ] AC-1.\n' > "$PLAN_REPO/$PLAN_SPEC"
git -C "$PLAN_REPO" add "$PLAN_DOC" "$PLAN_SPEC"
git -C "$PLAN_REPO" commit -q -m "declares refactor but spec present"
mkdir -p "$PLAN_REPO/docs/workflow/development-workflow"
cp "$PLAN_CHECKLIST_FIXTURES/well-formed.md" "$PLAN_REPO/docs/workflow/development-workflow/strict-plan-checks.md"
reset_mocks
install_recording_two_pass_mock
install_plan_gh_mock "$PLAN_DOC"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_plan_checks","findings":[]}'
export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
MOCK_PR_HEAD_BRANCH="implementation-plan/1655-7a"
MOCK_PR_HEAD_SHA="$(git -C "$PLAN_REPO" rev-parse HEAD)"
export MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
export LOCAL_AI_REVIEWER_COMMAND
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$PLAN_REPO"
run_test "1655_s7a_all_seven" "STRICT_PLAN_APPLIED=source_declaration,unspecified_step,spec_traceability,ac_test_coverage,phase_ordering,dependency_state,reversal_risk" "$(line_for STRICT_PLAN_APPLIED)"
rm -rf "$PLAN_REPO"

# Scenario 8: plan text comes from reviewed head via git show
PLAN_REPO="$(mktemp -d)"
git -C "$PLAN_REPO" init -q
git -C "$PLAN_REPO" config user.email "test@example.com"
git -C "$PLAN_REPO" config user.name "Test User"
printf '# Review\n' > "$PLAN_REPO/REVIEW.md"
git -C "$PLAN_REPO" add REVIEW.md
git -C "$PLAN_REPO" commit -q -m "fixture"
mkdir -p "$PLAN_REPO/$PLAN_DEV_DIR"
printf 'COMMITTED-PLAN-TEXT\n' > "$PLAN_REPO/$PLAN_DOC"
git -C "$PLAN_REPO" add "$PLAN_DOC"
git -C "$PLAN_REPO" commit -q -m "plan committed"
printf 'WORKTREE-ONLY-TEXT\n' > "$PLAN_REPO/$PLAN_DOC"
_s8_head="$(git -C "$PLAN_REPO" rev-parse HEAD)"
_s8_text="$(
  HARNESS_MODE=1 bash -c '
    source "'"$REVIEWER"'"
    REPO_ROOT="'"$PLAN_REPO"'"
    HEAD_SHA="'"$_s8_head"'"
    strict_git_show_at_head "'"$PLAN_DOC"'"
  '
)"
run_test "1655_s8_git_show_text" "COMMITTED-PLAN-TEXT" "$_s8_text"
rm -rf "$PLAN_REPO"

# Scenario 9 / P2: amendment PR supplies whole plan document, not diff hunks
PLAN_REPO="$(mktemp -d)"
git -C "$PLAN_REPO" init -q
git -C "$PLAN_REPO" config user.email "test@example.com"
git -C "$PLAN_REPO" config user.name "Test User"
printf '# Review\n' > "$PLAN_REPO/REVIEW.md"
git -C "$PLAN_REPO" add REVIEW.md
git -C "$PLAN_REPO" commit -q -m "fixture"
git -C "$PLAN_REPO" remote add origin "git@github.com:owner/repo.git"
mkdir -p "$PLAN_REPO/$PLAN_DEV_DIR"
python3 - <<'PY' "$PLAN_REPO/$PLAN_DOC"
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
body = "# Plan\n\n**Spec**: [spec](./1_1655-strict-plan-review-mode_specs.md)\n\n"
body += "".join(f"## Step {i}\n\nDo work item {i}.\n\n" for i in range(1, 121))
path.write_text(body)
PY
printf '# Spec\n\n- [ ] AC-1.\n' > "$PLAN_REPO/$PLAN_SPEC"
git -C "$PLAN_REPO" add "$PLAN_DOC" "$PLAN_SPEC"
git -C "$PLAN_REPO" commit -q -m "long plan"
mkdir -p "$PLAN_REPO/docs/workflow/development-workflow"
cp "$PLAN_CHECKLIST_FIXTURES/well-formed.md" "$PLAN_REPO/docs/workflow/development-workflow/strict-plan-checks.md"
_full_text="$(git -C "$PLAN_REPO" show "HEAD:$PLAN_DOC")"
reset_mocks
BUNDLE_DUMP="$(mktemp)"
cat > "$MOCK_BIN/local-reviewer-mock" <<'MOCK_REVIEWER'
#!/usr/bin/env bash
if [ -n "${MOCK_BUNDLE_DUMP:-}" ] && [ "${LOCAL_AI_REVIEWER_MODE:-ordinary}" = "strict" ]; then
  cp "$CONTEXT_BUNDLE_PATH" "$MOCK_BUNDLE_DUMP"
fi
if [ "${LOCAL_AI_REVIEWER_MODE:-ordinary}" = "strict" ]; then
  printf '%s\n' '{"mode":"strict_plan_checks","findings":[]}'
else
  printf '%s\n' '{"result":"clean","findings":[]}'
fi
MOCK_REVIEWER
chmod +x "$MOCK_BIN/local-reviewer-mock"
cat > "$MOCK_BIN/gh" <<MOCK_GH
#!/usr/bin/env bash
case "\$*" in
  *"pr view 123"*"--json baseRefName,headRefName,headRefOid"*)
    printf '{"baseRefName":"develop","headRefName":"implementation-plan/1655-s9","headRefOid":"%s"}\n' "\${MOCK_PR_HEAD_SHA}"
    exit 0
    ;;
  *"pr diff 123"*"--name-only"*)
    printf '%s\nREVIEW.md\n' "$PLAN_DOC"
    exit 0
    ;;
  *"pr diff 123"*)
    printf 'M\t%s\n' "$PLAN_DOC"
    exit 0
    ;;
  *) exit 1 ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"
MOCK_BUNDLE_DUMP="$BUNDLE_DUMP"
MOCK_PR_HEAD_BRANCH="implementation-plan/1655-s9"
MOCK_PR_HEAD_SHA="$(git -C "$PLAN_REPO" rev-parse HEAD)"
export MOCK_BUNDLE_DUMP MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
export LOCAL_AI_REVIEWER_COMMAND
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$PLAN_REPO"
_s9_text="$(jq -j -r '.strict_plan_documents[0].text' "$BUNDLE_DUMP")"
run_test "1655_s9_whole_document" "$_full_text" "$_s9_text"
rm -f "$BUNDLE_DUMP"
rm -rf "$PLAN_REPO"

# Scenario 10: two changed plan documents supplied with per-document sources (AC-13)
PLAN_REPO="$(mktemp -d)"
PLAN_DEV_A="docs/specs/developments/20260831062000_1655-strict-plan-review-mode"
PLAN_DEV_B="docs/specs/developments/20260831062001_1655-other"
PLAN_DOC_A="$PLAN_DEV_A/2_1655-strict-plan-review-mode_implementation-plan.md"
PLAN_SPEC_A="$PLAN_DEV_A/1_1655-strict-plan-review-mode_specs.md"
PLAN_DOC_B="$PLAN_DEV_B/2_1655-other_implementation-plan.md"
git -C "$PLAN_REPO" init -q
git -C "$PLAN_REPO" config user.email "test@example.com"
git -C "$PLAN_REPO" config user.name "Test User"
printf '# Review\n' > "$PLAN_REPO/REVIEW.md"
git -C "$PLAN_REPO" add REVIEW.md
git -C "$PLAN_REPO" commit -q -m "fixture"
git -C "$PLAN_REPO" remote add origin "git@github.com:owner/repo.git"
mkdir -p "$PLAN_REPO/$PLAN_DEV_A" "$PLAN_REPO/$PLAN_DEV_B"
printf '# Plan A\n\nSibling spec present.\n' > "$PLAN_REPO/$PLAN_DOC_A"
printf '# Spec A\n\n- [ ] AC-1.\n' > "$PLAN_REPO/$PLAN_SPEC_A"
printf '# Plan B\n\nNo sibling spec.\n' > "$PLAN_REPO/$PLAN_DOC_B"
git -C "$PLAN_REPO" add "$PLAN_DOC_A" "$PLAN_SPEC_A" "$PLAN_DOC_B"
git -C "$PLAN_REPO" commit -q -m "two plans"
mkdir -p "$PLAN_REPO/docs/workflow/development-workflow"
cp "$PLAN_CHECKLIST_FIXTURES/well-formed.md" "$PLAN_REPO/docs/workflow/development-workflow/strict-plan-checks.md"
reset_mocks
BUNDLE_DUMP="$(mktemp)"
cat > "$MOCK_BIN/local-reviewer-mock" <<'MOCK_REVIEWER'
#!/usr/bin/env bash
if [ -n "${MOCK_BUNDLE_DUMP:-}" ] && [ "${LOCAL_AI_REVIEWER_MODE:-ordinary}" = "strict" ]; then
  cp "$CONTEXT_BUNDLE_PATH" "$MOCK_BUNDLE_DUMP"
fi
if [ "${LOCAL_AI_REVIEWER_MODE:-ordinary}" = "strict" ]; then
  printf '%s\n' '{"mode":"strict_plan_checks","findings":[]}'
else
  printf '%s\n' '{"result":"clean","findings":[]}'
fi
MOCK_REVIEWER
chmod +x "$MOCK_BIN/local-reviewer-mock"
cat > "$MOCK_BIN/gh" <<MOCK_GH
#!/usr/bin/env bash
case "\$*" in
  *"pr view 123"*"--json baseRefName,headRefName,headRefOid"*)
    printf '{"baseRefName":"develop","headRefName":"implementation-plan/1655-s10","headRefOid":"%s"}\n' "\${MOCK_PR_HEAD_SHA}"
    exit 0
    ;;
  *"pr diff 123"*"--name-only"*)
    printf '%s\n%s\nREVIEW.md\n' "$PLAN_DOC_A" "$PLAN_DOC_B"
    exit 0
    ;;
  *) exit 1 ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"
MOCK_BUNDLE_DUMP="$BUNDLE_DUMP"
MOCK_PR_HEAD_BRANCH="implementation-plan/1655-s10"
MOCK_PR_HEAD_SHA="$(git -C "$PLAN_REPO" rev-parse HEAD)"
export MOCK_BUNDLE_DUMP MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
export LOCAL_AI_REVIEWER_COMMAND
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$PLAN_REPO"
run_test "1655_s10_two_documents" "2" "$(jq -r '.strict_plan_documents | length' "$BUNDLE_DUMP")"
run_test "1655_s10_doc_a_path" "$PLAN_DOC_A" "$(jq -r '.strict_plan_documents[0].path' "$BUNDLE_DUMP")"
run_test "1655_s10_doc_b_path" "$PLAN_DOC_B" "$(jq -r '.strict_plan_documents[1].path' "$BUNDLE_DUMP")"
run_test "1655_s10_doc_a_has_source" "true" "$(jq -r '.strict_plan_documents[0].has_source' "$BUNDLE_DUMP")"
run_test "1655_s10_doc_b_has_source" "false" "$(jq -r '.strict_plan_documents[1].has_source' "$BUNDLE_DUMP")"
run_test "1655_s10_one_source" "1" "$(jq -r '.strict_plan_sources | length' "$BUNDLE_DUMP")"
run_test "1655_s10_source_plan_a" "$PLAN_DOC_A" "$(jq -r '.strict_plan_sources[0].plan_path' "$BUNDLE_DUMP")"
rm -f "$BUNDLE_DUMP"
rm -rf "$PLAN_REPO"

# Scenario 11: git show failure → unavailable, one invocation
PLAN_REPO="$(mktemp -d)"
git -C "$PLAN_REPO" init -q
git -C "$PLAN_REPO" config user.email "test@example.com"
git -C "$PLAN_REPO" config user.name "Test User"
printf '# Review\n' > "$PLAN_REPO/REVIEW.md"
git -C "$PLAN_REPO" add REVIEW.md
git -C "$PLAN_REPO" commit -q -m "fixture"
git -C "$PLAN_REPO" remote add origin "git@github.com:owner/repo.git"
mkdir -p "$PLAN_REPO/docs/workflow/development-workflow"
cp "$PLAN_CHECKLIST_FIXTURES/well-formed.md" "$PLAN_REPO/docs/workflow/development-workflow/strict-plan-checks.md"
reset_mocks
install_recording_two_pass_mock
install_plan_gh_mock "$PLAN_DOC"
MOCK_RECORD_FILE="$(mktemp)"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
export MOCK_RECORD_FILE MOCK_ORDINARY_STDOUT
MOCK_PR_HEAD_BRANCH="implementation-plan/1655-s11"
MOCK_PR_HEAD_SHA="$(git -C "$PLAN_REPO" rev-parse HEAD)"
export MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
export LOCAL_AI_REVIEWER_COMMAND
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$PLAN_REPO"
run_test "1655_s11_unavailable" "STRICT_PLAN_STATE=unavailable" "$(line_for STRICT_PLAN_STATE)"
run_test "1655_s11_reason" "STRICT_PLAN_REASON=strict_pass_failed" "$(line_for STRICT_PLAN_REASON)"
run_test "1655_s11_one_invocation" "1" "$(grep -c '^mode=' "$MOCK_RECORD_FILE" || true)"
rm -f "$MOCK_RECORD_FILE"
rm -rf "$PLAN_REPO"

# Scenario 15 reverse: plan stage (fresh repo with spec sibling at HEAD)
PLAN_REPO="$(mktemp -d)"
git -C "$PLAN_REPO" init -q
git -C "$PLAN_REPO" config user.email "test@example.com"
git -C "$PLAN_REPO" config user.name "Test User"
printf '# Review\n' > "$PLAN_REPO/REVIEW.md"
git -C "$PLAN_REPO" add REVIEW.md
git -C "$PLAN_REPO" commit -q -m "fixture"
git -C "$PLAN_REPO" remote add origin "git@github.com:owner/repo.git"
mkdir -p "$PLAN_REPO/$PLAN_DEV_DIR"
cp "$REPO_ROOT/$PLAN_DOC" "$PLAN_REPO/$PLAN_DOC"
cp "$REPO_ROOT/$PLAN_SPEC" "$PLAN_REPO/$PLAN_SPEC"
git -C "$PLAN_REPO" add "$PLAN_DOC" "$PLAN_SPEC"
git -C "$PLAN_REPO" commit -q -m "plan-with-spec"
mkdir -p "$PLAN_REPO/docs/workflow/development-workflow"
cp "$PLAN_CHECKLIST_FIXTURES/well-formed.md" "$PLAN_REPO/docs/workflow/development-workflow/strict-plan-checks.md"
cp "$CHECKLIST_FIXTURES/well-formed.md" "$PLAN_REPO/docs/workflow/development-workflow/strict-spec-checks.md"
reset_mocks
install_recording_two_pass_mock
install_plan_gh_mock "$PLAN_DOC"
MOCK_RECORD_FILE="$(mktemp)"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
MOCK_STRICT_STDOUT='{"mode":"strict_plan_checks","findings":[]}'
export MOCK_RECORD_FILE MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
MOCK_PR_HEAD_BRANCH="implementation-plan/1655-test"
MOCK_PR_HEAD_SHA="$(git -C "$PLAN_REPO" rev-parse HEAD)"
export MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
export LOCAL_AI_REVIEWER_COMMAND
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$PLAN_REPO"
run_test "1655_s15_plan_applied" "STRICT_PLAN_STATE=applied" "$(line_for STRICT_PLAN_STATE)"
run_test "1655_s15_spec_na" "STRICT_SPEC_STATE=not_applicable" "$(line_for STRICT_SPEC_STATE)"
run_test "1655_s15_no_spec_reason" "no" "$(key_present STRICT_SPEC_REASON)"
run_test "1655_s15_plan_applied_set7" "STRICT_PLAN_APPLIED=source_declaration,unspecified_step,spec_traceability,ac_test_coverage,phase_ordering,dependency_state,reversal_risk" "$(line_for STRICT_PLAN_APPLIED)"
run_test "1655_s15_bundle_has_plan_docs" "true" "$(awk -F= '/^has_strict_plan_documents=/{print $2}' "$MOCK_RECORD_FILE" | tail -1)"
rm -f "$MOCK_RECORD_FILE"
rm -rf "$PLAN_REPO"

# Scenario 13: runbook-only plan stage PR
reset_mocks
install_recording_two_pass_mock
install_plan_checklist_into_repo "$PLAN_CHECKLIST_FIXTURES/well-formed.md"
install_plan_gh_mock "docs/testing/workflow/1655-strict-plan-review-mode.smoke-test.md"
MOCK_RECORD_FILE="$(mktemp)"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
export MOCK_RECORD_FILE MOCK_ORDINARY_STDOUT
run_plan_review
run_test "1655_s13_runbook_only" "STRICT_PLAN_STATE=not_applicable" "$(line_for STRICT_PLAN_STATE)"
run_test "1655_s13_reason" "STRICT_PLAN_REASON=no_plan_document_changed" "$(line_for STRICT_PLAN_REASON)"
run_test "1655_s13_one_invocation" "1" "$(grep -c '^mode=' "$MOCK_RECORD_FILE" || true)"
rm -f "$MOCK_RECORD_FILE"

# Scenario 14b: shipped plan identifiers
EXPECTED_PLAN_IDS='["source_declaration","unspecified_step","spec_traceability","ac_test_coverage","phase_ordering","dependency_state","reversal_risk"]'
EXTRACTED_PLAN_IDS="$(
  HARNESS_MODE=1 bash -c '
    source "'"$REVIEWER"'"
    extract_strict_checklist_known_checks "'"$SHIPPED_PLAN_CHECKLIST"'"
  ' | jq -c 'sort'
)"
run_test "1655_s14b_shipped_ids" "$(printf '%s\n' "$EXPECTED_PLAN_IDS" | jq -c 'sort')" "$EXTRACTED_PLAN_IDS"

EXPECTED_PLAN_SOURCES='[{"id":"ac_test_coverage","source":"required"},{"id":"dependency_state","source":"not_required"},{"id":"phase_ordering","source":"not_required"},{"id":"reversal_risk","source":"not_required"},{"id":"source_declaration","source":"not_required"},{"id":"spec_traceability","source":"required"},{"id":"unspecified_step","source":"required"}]'
EXTRACTED_PLAN_SOURCES="$(
  HARNESS_MODE=1 bash -c '
    source "'"$REVIEWER"'"
    extract_strict_plan_sections "'"$SHIPPED_PLAN_CHECKLIST"'"
  ' | jq -c 'sort_by(.id)'
)"
run_test "1655_s14b_shipped_sources" "$EXPECTED_PLAN_SOURCES" "$EXTRACTED_PLAN_SOURCES"

# Scenario 14c/14d: malformed Source metadata refused
run_test "1655_s14c_extract_refused" "1" "$(
  HARNESS_MODE=1 bash -c '
    source "'"$REVIEWER"'"
    extract_strict_plan_sections "'"$PLAN_CHECKLIST_FIXTURES/compensating-duplicate-source.md"'" >/dev/null && echo 0 || echo 1
  '
)"
run_test "1655_s14d_extract_refused" "1" "$(
  HARNESS_MODE=1 bash -c '
    source "'"$REVIEWER"'"
    extract_strict_plan_sections "'"$PLAN_CHECKLIST_FIXTURES/missing-source-last.md"'" >/dev/null && echo 0 || echo 1
  '
)"
run_test "1655_s14e_extract_refused" "1" "$(
  HARNESS_MODE=1 bash -c '
    source "'"$REVIEWER"'"
    extract_strict_plan_sections "'"$PLAN_CHECKLIST_FIXTURES/invalid-source-value.md"'" >/dev/null && echo 0 || echo 1
  '
)"
reset_mocks
install_recording_two_pass_mock
install_plan_checklist_into_repo "$PLAN_CHECKLIST_FIXTURES/invalid-source-value.md"
install_plan_gh_mock "$PLAN_DOC"
install_plan_artifacts 1
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
export MOCK_ORDINARY_STDOUT
MOCK_PR_HEAD_BRANCH="implementation-plan/1655-14e"
MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
export MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
run_plan_review
run_test "1655_s14e_unavailable" "STRICT_PLAN_STATE=unavailable" "$(line_for STRICT_PLAN_STATE)"
run_test "1655_s14e_reason" "STRICT_PLAN_REASON=checklist_unreadable" "$(line_for STRICT_PLAN_REASON)"
run_test "1655_s14e_no_count" "no" "$(key_present STRICT_PLAN_COUNT)"
reset_mocks
install_recording_two_pass_mock
install_plan_checklist_into_repo "$PLAN_CHECKLIST_FIXTURES/compensating-duplicate-source.md"
install_plan_gh_mock "$PLAN_DOC"
install_plan_artifacts 1
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
export MOCK_ORDINARY_STDOUT
MOCK_PR_HEAD_BRANCH="implementation-plan/1655-14c"
MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
export MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
run_plan_review
run_test "1655_s14c_unavailable" "STRICT_PLAN_STATE=unavailable" "$(line_for STRICT_PLAN_STATE)"
run_test "1655_s14c_reason" "STRICT_PLAN_REASON=checklist_unreadable" "$(line_for STRICT_PLAN_REASON)"
run_test "1655_s14c_no_count" "no" "$(key_present STRICT_PLAN_COUNT)"

# Scenarios 20/21: planted-violation fail/pass pairs per strict plan check (harness)
STRICT_PLAN_POSITIVES="$FIXTURES/strict-plan-plans"
STRICT_PLAN_POSITIVES_PASS="$FIXTURES/strict-plan-plans-pass"

run_planted_plan_fixture_review() {
  local fixture_name="$1"
  local variant="$2"
  local strict_json="$3"
  local fixture_root dev_dir plan_file
  case "$variant" in
    fail) fixture_root="$STRICT_PLAN_POSITIVES" ;;
    pass) fixture_root="$STRICT_PLAN_POSITIVES_PASS" ;;
    *) return 1 ;;
  esac
  dev_dir="docs/specs/developments/strict-fixture-${fixture_name}"
  plan_file="$dev_dir/2_${fixture_name}_implementation-plan.md"
  PLAN_REPO="$(mktemp -d)"
  git -C "$PLAN_REPO" init -q
  git -C "$PLAN_REPO" config user.email "test@example.com"
  git -C "$PLAN_REPO" config user.name "Test User"
  printf '# Review\n' > "$PLAN_REPO/REVIEW.md"
  git -C "$PLAN_REPO" add REVIEW.md
  git -C "$PLAN_REPO" commit -q -m "fixture"
  git -C "$PLAN_REPO" remote add origin "git@github.com:owner/repo.git"
  mkdir -p "$PLAN_REPO/docs/workflow/development-workflow"
  cp "$PLAN_CHECKLIST_FIXTURES/well-formed.md" "$PLAN_REPO/docs/workflow/development-workflow/strict-plan-checks.md"
  mkdir -p "$PLAN_REPO/$dev_dir"
  cp "$fixture_root/$fixture_name/"*.md "$PLAN_REPO/$dev_dir/"
  git -C "$PLAN_REPO" add -A
  git -C "$PLAN_REPO" commit -q -m "planted $fixture_name $variant"
  reset_mocks
  install_recording_two_pass_mock
  cat > "$MOCK_BIN/gh" <<MOCK_GH
#!/usr/bin/env bash
case "\$*" in
  *"pr view 123"*"--json baseRefName,headRefName,headRefOid"*)
    printf '{"baseRefName":"develop","headRefName":"implementation-plan/1655-planted-${fixture_name}","headRefOid":"%s"}\n' "\${MOCK_PR_HEAD_SHA}"
    exit 0
    ;;
  *"pr diff 123"*"--name-only"*)
    printf '%s\nREVIEW.md\n' "$plan_file"
    exit 0
    ;;
  *) exit 1 ;;
esac
MOCK_GH
  chmod +x "$MOCK_BIN/gh"
  MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
  MOCK_STRICT_STDOUT="$strict_json"
  export MOCK_ORDINARY_STDOUT MOCK_STRICT_STDOUT
  MOCK_PR_HEAD_BRANCH="implementation-plan/1655-planted-${fixture_name}"
  MOCK_PR_HEAD_SHA="$(git -C "$PLAN_REPO" rev-parse HEAD)"
  export MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
  LOCAL_AI_REVIEWER_COMMAND=local-reviewer-mock
  export LOCAL_AI_REVIEWER_COMMAND
  run_reviewer "$MOCK_BIN:$PATH" --repo-root "$PLAN_REPO"
  rm -rf "$PLAN_REPO"
}

_planted_checks=(
  "source_declaration:1"
  "unspecified_step:8"
  "spec_traceability:7"
  "ac_test_coverage:11"
  "phase_ordering:7"
  "dependency_state:7"
  "reversal_risk:7"
)
for _entry in "${_planted_checks[@]}"; do
  _check="${_entry%%:*}"
  _line="${_entry##*:}"
  _fail_json='{"mode":"strict_plan_checks","findings":[{"check":"'"$_check"'","path":"docs/specs/developments/strict-fixture-'"$_check"'/2_'"$_check"'_implementation-plan.md","line":'"$_line"',"body":"planted violation"}]}'
  run_planted_plan_fixture_review "$_check" fail "$_fail_json"
  run_test "1655_s20_${_check}_fail" "STRICT_1_CHECK=${_check}" "$(line_for STRICT_1_CHECK)"
  run_test "1655_s20_${_check}_fail_line" "STRICT_1_LINE=${_line}" "$(line_for STRICT_1_LINE)"
  _pass_json='{"mode":"strict_plan_checks","findings":[]}'
  run_planted_plan_fixture_review "$_check" pass "$_pass_json"
  _checks_line="$(line_for STRICT_PLAN_CHECKS 2>/dev/null || true)"
  if printf '%s' "$_checks_line" | grep -q "$_check"; then
    _has_check=yes
  else
    _has_check=no
  fi
  run_test "1655_s21_${_check}_pass" "no" "$_has_check"
done

# Scenario 16: evidence includes strict_plan on every local reviewer round
reset_mocks
install_recording_two_pass_mock
install_plan_checklist_into_repo "$PLAN_CHECKLIST_FIXTURES/well-formed.md"
LOCAL_AI_REVIEWER_EVIDENCE_FILE="$EVIDENCE_FILE"
MOCK_ORDINARY_STDOUT='{"result":"clean","findings":[]}'
export LOCAL_AI_REVIEWER_EVIDENCE_FILE MOCK_ORDINARY_STDOUT
MOCK_PR_HEAD_BRANCH="feature/test"
MOCK_PR_HEAD_SHA="$(git -C "$VALID_REPO_ROOT" rev-parse HEAD)"
export MOCK_PR_HEAD_BRANCH MOCK_PR_HEAD_SHA
run_reviewer "$MOCK_BIN:$PATH" --repo-root "$VALID_REPO_ROOT"
run_test "1655_s16_evidence_has_plan" "true" "$(jq -r 'has("strict_plan")' "$EVIDENCE_FILE")"
run_test "1655_s16_evidence_plan_state" "not_applicable" "$(jq -r '.strict_plan.state' "$EVIDENCE_FILE")"

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"
