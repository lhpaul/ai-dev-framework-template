#!/usr/bin/env bash
# Dispatch and behavior tests for the Ronda pr-review-loop platform (#1786).
# covers: scripts/development-workflow/pr-review-loop.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

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

HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

# ---------------------------------------------------------------------------
# Area 1: bot_login_for_platform — ronda platform
# ---------------------------------------------------------------------------
echo "=== Area 1: bot_login_for_platform — ronda ==="

unset RONDA_BOT_LOGIN
actual="$(bot_login_for_platform "ronda")"
run_test "ronda_bot_login_default" "ronda[bot]" "$actual"

export RONDA_BOT_LOGIN="custom-ronda-bot[bot]"
actual="$(bot_login_for_platform "ronda")"
run_test "ronda_bot_login_env_override" "custom-ronda-bot[bot]" "$actual"
unset RONDA_BOT_LOGIN

# ---------------------------------------------------------------------------
# Area 2: run_platform_review routes "ronda" to run_ronda_review
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2: run_platform_review dispatch ==="

_ronda_dispatch_called=0
run_ronda_review() {
  _ronda_dispatch_called=1
  print_kv RESULT clean
  print_kv PLATFORM ronda
  print_kv COMMENT_COUNT 0
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
}
run_platform_review "ronda" "999" "feature/test" "1" "5" >/dev/null 2>&1 || true
run_test "run_platform_review_routes_to_ronda" "1" "$_ronda_dispatch_called"
unset -f run_ronda_review
unset _ronda_dispatch_called

# Re-source to restore the real run_ronda_review definition for Area 3+.
HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

# ---------------------------------------------------------------------------
# Area 3: run_ronda_review — exit-code and key-value output contract
#
#   3.1  head-sha-unavailable  -> RESULT=escalate REASON=head-sha-unavailable, exit 2
#   3.2  absence-then-clean    -> absence of the check run is NOT treated as
#                                 clean/skipped; polling continues until a
#                                 completed conclusion=success run appears
#                                 -> RESULT=clean, exit 0
#   3.3  pass failed           -> conclusion=failure (the pass could not
#                                 complete) -> RESULT=escalate
#                                 REASON=ronda_pass_failed, check-run title
#                                 carried, no synthesized findings, exit 2
#   3.4  action_required       -> outside Ronda's contract -> RESULT=escalate
#                                 REASON=ronda_unexpected_conclusion, exit 2
#   3.5  timeout                -> max_wait=0, no completed run observed
#                                 -> RESULT=escalate REASON=timeout, exit 2
#   3.6  fetch-failed           -> check-runs API call fails
#                                 -> RESULT=escalate REASON=fetch-failed, exit 2
#   3.7  unexpected conclusion  -> conclusion=neutral
#                                 -> RESULT=escalate REASON=ronda_unexpected_conclusion, exit 2
#
# Each test that exercises run_ronda_review requires a custom gh mock because
# the function issues several incompatible gh API call shapes in a single run
# (pulls API headRefOid, check-runs API, PR reviews API, review-comments API).
# The per-test custom mock is written to a temp directory and placed on PATH
# before calling run_ronda_review, mirroring the bugbot/copilot test pattern.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 3: run_ronda_review — clean / needs_fixes / escalate ==="

_ronda_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  _interruptible_sleep() { :; }
'

# --- Test 3.1: escalate (head-sha-unavailable) ---
_ronda_mock_31="$(mktemp -d)"
cat > "$_ronda_mock_31/gh" <<'RONDA_GH_31'
#!/usr/bin/env bash
case "$*" in
  *"headRefOid"*)
    printf '\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
RONDA_GH_31
chmod +x "$_ronda_mock_31/gh"

unset RONDA_BOT_LOGIN RONDA_CHECK_NAME
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_ronda_overrides"
  _ec=0
  PATH="$_ronda_mock_31:$PATH" run_ronda_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "ronda_head_sha_unavailable_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "ronda_head_sha_unavailable_reason" "REASON=head-sha-unavailable" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "ronda_head_sha_unavailable_exit_code" "2" "$actual_exit"
rm -rf "$_ronda_mock_31"
unset _ronda_mock_31 actual_output actual_exit

# --- Test 3.2: absence-then-clean (poll continues past an absent check run) ---
_ronda_mock_32="$(mktemp -d)"
printf '0\n' > "$_ronda_mock_32/check_calls"
cat > "$_ronda_mock_32/gh" <<'RONDA_GH_32'
#!/usr/bin/env bash
case "$*" in
  *"headRefOid"*)
    printf 'abc32sha\n'; exit 0 ;;
  *"check-runs"*)
    calls_file="$(dirname "$0")/check_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -eq 1 ]; then
      # Absence: no "Ronda review" check run for this head SHA yet.
      printf '{"check_runs":[]}\n'
    else
      printf '{"check_runs":[{"name":"Ronda review","status":"completed","conclusion":"success","started_at":"2020-01-01T00:00:00Z","output":{"title":"Review posted — no findings","summary":"Model: m\\nDuration: 1s\\nBlocking: 0, Important: 0, Nit: 0"}}]}\n'
    fi
    exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
RONDA_GH_32
chmod +x "$_ronda_mock_32/gh"

unset RONDA_BOT_LOGIN RONDA_CHECK_NAME
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_ronda_overrides"
  _ec=0
  PATH="$_ronda_mock_32:$PATH" run_ronda_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "ronda_absence_then_clean_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "ronda_absence_then_clean_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "ronda_absence_then_clean_reviewed_head" "REVIEWED_HEAD=abc32sha" \
  "$(printf '%s\n' "$actual_output" | grep "^REVIEWED_HEAD=")"
run_test "ronda_absence_then_clean_exit_code" "0" "$actual_exit"
run_test "ronda_absence_then_clean_polled_twice" "2" \
  "$(cat "$_ronda_mock_32/check_calls")"
rm -rf "$_ronda_mock_32"
unset _ronda_mock_32 actual_output actual_exit

# --- Test 3.3: pass failure — conclusion=failure is NOT blocking findings ---
# Ronda's contract (#1849): `failure` means the pass could not complete
# (credential missing, timeout, model unavailable, ...). It must escalate with
# the check-run title as the reason, never report synthesized findings — even
# when a review with inline comments exists for the head.
_ronda_mock_33="$(mktemp -d)"
cat > "$_ronda_mock_33/gh" <<'RONDA_GH_33'
#!/usr/bin/env bash
case "$*" in
  *"headRefOid"*)
    printf 'abc33sha\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Ronda review","status":"completed","conclusion":"failure","started_at":"2020-01-01T00:00:00Z","output":{"title":"Review failed — credential missing or invalid","summary":"Model: m\\nDuration: 1s\\nReason: credential missing or invalid"}}]}\n'
    exit 0 ;;
  *"/comments"*)
    printf '[{"id":1,"body":"finding one"},{"id":2,"body":"finding two"}]\n'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"id":789,"user":{"login":"ronda[bot]"},"commit_id":"abc33sha","state":"CHANGES_REQUESTED"}]\n'
    exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
RONDA_GH_33
chmod +x "$_ronda_mock_33/gh"

unset RONDA_BOT_LOGIN RONDA_CHECK_NAME
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_ronda_overrides"
  _ec=0
  PATH="$_ronda_mock_33:$PATH" run_ronda_review "42" "feature/42-test" "1" "5" 2>/dev/null || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "ronda_pass_failed_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "ronda_pass_failed_reason" "REASON=ronda_pass_failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "ronda_pass_failed_title" "RONDA_CHECK_TITLE=Review failed — credential missing or invalid" \
  "$(printf '%s\n' "$actual_output" | grep "^RONDA_CHECK_TITLE=")"
run_test "ronda_pass_failed_no_blocking_count" "" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=" || true)"
run_test "ronda_pass_failed_exit_code" "2" "$actual_exit"
rm -rf "$_ronda_mock_33"
unset _ronda_mock_33 actual_output actual_exit

# --- Test 3.4: action_required is outside Ronda's contract -> fail closed ---
_ronda_mock_34="$(mktemp -d)"
cat > "$_ronda_mock_34/gh" <<'RONDA_GH_34'
#!/usr/bin/env bash
case "$*" in
  *"headRefOid"*)
    printf 'abc34sha\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Ronda review","status":"completed","conclusion":"action_required","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
RONDA_GH_34
chmod +x "$_ronda_mock_34/gh"

unset RONDA_BOT_LOGIN RONDA_CHECK_NAME
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_ronda_overrides"
  _ec=0
  PATH="$_ronda_mock_34:$PATH" run_ronda_review "42" "feature/42-test" "1" "5" 2>/dev/null || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "ronda_action_required_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "ronda_action_required_reason" "REASON=ronda_unexpected_conclusion" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "ronda_action_required_exit_code" "2" "$actual_exit"
rm -rf "$_ronda_mock_34"
unset _ronda_mock_34 actual_output actual_exit

# --- Test 3.5: escalate (timeout) — max_wait=0, no completed run observed ---
_ronda_mock_35="$(mktemp -d)"
cat > "$_ronda_mock_35/gh" <<'RONDA_GH_35'
#!/usr/bin/env bash
case "$*" in
  *"headRefOid"*)
    printf 'abc35sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
RONDA_GH_35
chmod +x "$_ronda_mock_35/gh"

unset RONDA_BOT_LOGIN RONDA_CHECK_NAME
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_ronda_overrides"
  _ec=0
  PATH="$_ronda_mock_35:$PATH" run_ronda_review "42" "feature/42-test" "1" "0" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "ronda_timeout_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "ronda_timeout_reason" "REASON=timeout" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "ronda_timeout_exit_code" "2" "$actual_exit"
rm -rf "$_ronda_mock_35"
unset _ronda_mock_35 actual_output actual_exit

# --- Test 3.6: escalate (fetch-failed) — check-runs API call fails ---
_ronda_mock_36="$(mktemp -d)"
cat > "$_ronda_mock_36/gh" <<'RONDA_GH_36'
#!/usr/bin/env bash
case "$*" in
  *"headRefOid"*)
    printf 'abc36sha\n'; exit 0 ;;
  *"check-runs"*)
    exit 1 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
RONDA_GH_36
chmod +x "$_ronda_mock_36/gh"

unset RONDA_BOT_LOGIN RONDA_CHECK_NAME
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_ronda_overrides"
  _ec=0
  PATH="$_ronda_mock_36:$PATH" run_ronda_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "ronda_fetch_failed_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "ronda_fetch_failed_reason" "REASON=fetch-failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "ronda_fetch_failed_exit_code" "2" "$actual_exit"
rm -rf "$_ronda_mock_36"
unset _ronda_mock_36 actual_output actual_exit

# --- Test 3.7: escalate (unexpected conclusion) — conclusion=neutral ---
_ronda_mock_37="$(mktemp -d)"
cat > "$_ronda_mock_37/gh" <<'RONDA_GH_37'
#!/usr/bin/env bash
case "$*" in
  *"headRefOid"*)
    printf 'abc37sha\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Ronda review","status":"completed","conclusion":"neutral","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
RONDA_GH_37
chmod +x "$_ronda_mock_37/gh"

unset RONDA_BOT_LOGIN RONDA_CHECK_NAME
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_ronda_overrides"
  _ec=0
  PATH="$_ronda_mock_37:$PATH" run_ronda_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "ronda_unexpected_conclusion_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "ronda_unexpected_conclusion_reason" "REASON=ronda_unexpected_conclusion" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "ronda_unexpected_conclusion_exit_code" "2" "$actual_exit"
rm -rf "$_ronda_mock_37"
unset _ronda_mock_37 actual_output actual_exit

# --- Test 3.8: initial headRefOid lookup is scoped to the target repo ---
# Bugbot finding: the initial head-SHA lookup omitted --repo while every
# later poll call passes it, so a product-repo target (WORKFLOW_TARGET_GITHUB_REPO
# / --repo) would resolve the initial SHA against the wrong repository and
# escalate with head-sha-unavailable instead of ever polling the intended PR.
_ronda_mock_38="$(mktemp -d)"
cat > "$_ronda_mock_38/gh" <<'RONDA_GH_38'
#!/usr/bin/env bash
case "$*" in
  *"headRefOid"*)
    case "$*" in
      *"--repo owner/repo"*) printf 'abc38sha\n'; exit 0 ;;
      *) printf '\n'; exit 0 ;;
    esac ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Ronda review","status":"completed","conclusion":"success","started_at":"2020-01-01T00:00:00Z","output":{"title":"Review posted — no findings","summary":"Model: m\\nDuration: 1s\\nBlocking: 0, Important: 0, Nit: 0"}}]}\n'
    exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
RONDA_GH_38
chmod +x "$_ronda_mock_38/gh"

unset RONDA_BOT_LOGIN RONDA_CHECK_NAME
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_ronda_overrides"
  _ec=0
  PATH="$_ronda_mock_38:$PATH" run_ronda_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "ronda_initial_lookup_repo_scoped_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "ronda_initial_lookup_repo_scoped_exit_code" "0" "$actual_exit"
rm -rf "$_ronda_mock_38"
unset _ronda_mock_38 actual_output actual_exit

# ---------------------------------------------------------------------------
# Area 4: conclusion=success — verdict read from the summary severity line
# (#1849). A `success` conclusion only means the pass completed; the
# `Blocking: N, Important: N, Nit: N` summary line carries the verdict.
#
#   4.1  Blocking: 1 (planted)     -> needs_fixes, BLOCKING_COUNT=1, exit 1
#                                     (the case the pre-#1849 mapping reported
#                                     clean); the review is authored by
#                                     github-actions[bot] and no review lookup
#                                     is required
#   4.2  Blocking: 0 + suggestions -> clean, SUGGESTION_COUNT=Important+Nit
#   4.3  severity line missing     -> escalate ronda_severity_unparseable
#   4.4  severity line malformed   -> escalate ronda_severity_unparseable
#   4.5  severity line duplicated  -> escalate ronda_severity_unparseable
#   4.6  leading-zero counts       -> read as base 10 (08 is 8, not an octal
#                                     arithmetic error)
#   4.7  CRLF line endings         -> parsed (carriage returns stripped)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 4: success conclusion — severity-line verdict ==="

# _ronda_run_success_summary <summary-json-string> — runs run_ronda_review
# against a mock whose "Ronda review" check run concluded success with the
# given JSON-encoded output.summary, and prints the key=value output plus
# EXIT=<code>. The mock serves a github-actions[bot] review for the head and
# counts every reviews/comments call so the tests can prove the verdict path
# no longer depends on a review-author lookup.
_ronda_run_success_summary() {
  local summary_json="$1"
  local mock_dir
  mock_dir="$(mktemp -d)"
  printf '0\n' > "$mock_dir/review_calls"
  printf '%s' "{\"check_runs\":[{\"name\":\"Ronda review\",\"status\":\"completed\",\"conclusion\":\"success\",\"started_at\":\"2020-01-01T00:00:00Z\",\"output\":{\"title\":\"Review posted\",\"summary\":$summary_json}}]}" \
    > "$mock_dir/check_runs.json"
  cat > "$mock_dir/gh" <<'RONDA_GH_4'
#!/usr/bin/env bash
dir="$(dirname "$0")"
case "$*" in
  *"headRefOid"*)
    printf 'abc4sha\n'; exit 0 ;;
  *"check-runs"*)
    cat "$dir/check_runs.json"; printf '\n'; exit 0 ;;
  *"/reviews"*|*"/comments"*)
    n="$(cat "$dir/review_calls")"; printf '%s\n' "$((n + 1))" > "$dir/review_calls"
    printf '[{"id":7,"user":{"login":"github-actions[bot]"},"commit_id":"abc4sha","state":"COMMENTED","body":"## Ronda review"}]\n'
    exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
RONDA_GH_4
  chmod +x "$mock_dir/gh"
  (
    eval "$_ronda_overrides"
    unset RONDA_BOT_LOGIN RONDA_CHECK_NAME
    _ec=0
    PATH="$mock_dir:$PATH" run_ronda_review "42" "feature/42-test" "1" "5" 2>/dev/null || _ec=$?
    printf 'EXIT=%s\n' "$_ec"
  )
  printf 'REVIEW_CALLS=%s\n' "$(cat "$mock_dir/review_calls")"
  rm -rf "$mock_dir"
}

_kv() { printf '%s\n' "$2" | grep "^$1=" || true; }

# --- Test 4.1: planted Blocking: 1 must be needs_fixes, not clean ---
out="$(_ronda_run_success_summary '"Model: m\nDuration: 3s\nBlocking: 1, Important: 0, Nit: 0"')"
run_test "ronda_success_blocking_result" "RESULT=needs_fixes" "$(_kv RESULT "$out")"
run_test "ronda_success_blocking_reason" "REASON=ronda_blocking_findings" "$(_kv REASON "$out")"
run_test "ronda_success_blocking_count" "BLOCKING_COUNT=1" "$(_kv BLOCKING_COUNT "$out")"
run_test "ronda_success_blocking_comment_count" "COMMENT_COUNT=1" "$(_kv COMMENT_COUNT "$out")"
run_test "ronda_success_blocking_reviewed_head" "REVIEWED_HEAD=abc4sha" "$(_kv REVIEWED_HEAD "$out")"
run_test "ronda_success_blocking_exit_code" "EXIT=1" "$(_kv EXIT "$out")"
run_test "ronda_success_blocking_no_review_lookup" "REVIEW_CALLS=0" "$(_kv REVIEW_CALLS "$out")"

# --- Test 4.2: Blocking: 0 with Important/Nit findings is clean + suggestions ---
out="$(_ronda_run_success_summary '"Model: m\nDuration: 3s\nBlocking: 0, Important: 1, Nit: 2\nCategory-forced sweep:\n- x: clear"')"
run_test "ronda_success_suggestions_result" "RESULT=clean" "$(_kv RESULT "$out")"
run_test "ronda_success_suggestions_blocking" "BLOCKING_COUNT=0" "$(_kv BLOCKING_COUNT "$out")"
run_test "ronda_success_suggestions_count" "SUGGESTION_COUNT=3" "$(_kv SUGGESTION_COUNT "$out")"
run_test "ronda_success_suggestions_comment_count" "COMMENT_COUNT=3" "$(_kv COMMENT_COUNT "$out")"
run_test "ronda_success_suggestions_exit_code" "EXIT=0" "$(_kv EXIT "$out")"

# --- Test 4.3: severity line missing -> fail closed ---
out="$(_ronda_run_success_summary '"Model: m\nDuration: 3s"')"
run_test "ronda_success_missing_line_result" "RESULT=escalate" "$(_kv RESULT "$out")"
run_test "ronda_success_missing_line_reason" "REASON=ronda_severity_unparseable" "$(_kv REASON "$out")"
run_test "ronda_success_missing_line_exit_code" "EXIT=2" "$(_kv EXIT "$out")"

# --- Test 4.3b: no output.summary at all -> fail closed ---
out="$(_ronda_run_success_summary 'null')"
run_test "ronda_success_null_summary_reason" "REASON=ronda_severity_unparseable" "$(_kv REASON "$out")"
run_test "ronda_success_null_summary_exit_code" "EXIT=2" "$(_kv EXIT "$out")"

# --- Test 4.4: malformed severity line (non-numeric / reordered) -> fail closed ---
out="$(_ronda_run_success_summary '"Blocking: one, Important: 0, Nit: 0\nImportant: 0, Blocking: 1, Nit: 0"')"
run_test "ronda_success_malformed_line_reason" "REASON=ronda_severity_unparseable" "$(_kv REASON "$out")"
run_test "ronda_success_malformed_line_exit_code" "EXIT=2" "$(_kv EXIT "$out")"

# --- Test 4.5: two severity lines are ambiguous -> fail closed ---
out="$(_ronda_run_success_summary '"Blocking: 0, Important: 0, Nit: 0\nBlocking: 2, Important: 0, Nit: 0"')"
run_test "ronda_success_duplicate_line_reason" "REASON=ronda_severity_unparseable" "$(_kv REASON "$out")"
run_test "ronda_success_duplicate_line_exit_code" "EXIT=2" "$(_kv EXIT "$out")"

# --- Test 4.6: leading zeros are base 10 ---
out="$(_ronda_run_success_summary '"Blocking: 08, Important: 09, Nit: 010"')"
run_test "ronda_success_leading_zero_blocking" "BLOCKING_COUNT=8" "$(_kv BLOCKING_COUNT "$out")"
run_test "ronda_success_leading_zero_suggestions" "SUGGESTION_COUNT=19" "$(_kv SUGGESTION_COUNT "$out")"
run_test "ronda_success_leading_zero_exit_code" "EXIT=1" "$(_kv EXIT "$out")"

# --- Test 4.7: CRLF line endings still parse ---
out="$(_ronda_run_success_summary '"Model: m\r\nBlocking: 2, Important: 0, Nit: 0\r\n"')"
run_test "ronda_success_crlf_blocking" "BLOCKING_COUNT=2" "$(_kv BLOCKING_COUNT "$out")"
run_test "ronda_success_crlf_exit_code" "EXIT=1" "$(_kv EXIT "$out")"

unset out
unset -f _ronda_run_success_summary _kv

unset _ronda_overrides

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo ""
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo ""
echo "PASS: $PASS_COUNT test(s) passed"
