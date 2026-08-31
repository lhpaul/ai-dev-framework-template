#!/usr/bin/env bash
# Unit tests for local-ai-reviewer.sh.
# covers: scripts/development-workflow/local-ai-reviewer.sh

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
  git -C "$VALID_REPO_ROOT" add docs/workflow/development-workflow/strict-spec-checks.md >/dev/null 2>&1 || true
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
  "$(rg -n 'LOCAL_AI_REVIEWER_STRICT_TIMEOUT|STRICT_SPEC_TIMEOUT' "$REVIEWER" >/dev/null && echo no || echo yes)"
run_test "s9d_help_no_second_timeout_knob" "yes" \
  "$(bash "$REVIEWER" --help 2>&1 | rg -q 'LOCAL_AI_REVIEWER_STRICT_TIMEOUT|STRICT_SPEC_TIMEOUT' && echo no || echo yes)"

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
  "$(rg -q 'LOCAL_AI_REVIEWER_MODE' "$CODEX_CMD" && echo yes || echo no)"
run_test "s11a_codex_strict_prompt_override" "yes" \
  "$(rg -q 'LOCAL_CODEX_REVIEWER_STRICT_PROMPT' "$CODEX_CMD" && echo yes || echo no)"

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"
