#!/usr/bin/env bash
# test-expensive-gate-config-error.sh — issue #1817 regression suite.
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md
# covers: docs/workflow/development-workflow/integrations/codex-github.md
# covers: docs/workflow/development-workflow/integrations/pr-review-platform.md
#
# An expensive reviewer (codex-github) needs current-head local-ai-reviewer
# evidence. When local-ai-reviewer is in no configured platform list, that
# condition can never be met. Before #1817 the gate deferred anyway, so the loop
# reported RESULT=needs_fixes / expensive_gate_deferred with zero findings and
# zero threads until the deferral cap. The gate must now fail fast as a
# configuration error with a distinct, actionable escalation reason.
# shellcheck shell=bash disable=SC2034
# SC2034: test globals are read by functions sourced from pr-review-loop.sh.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
LOOP_SCRIPT="$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name — expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_contains() {
  local name="$1" needle="$2" file="$3"
  if grep -Fq -- "$needle" "$file"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name — expected substring '${needle}' in ${file}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

export MOCK_REPO_ROOT="$REPO_ROOT"
# shellcheck source=scripts/development-workflow/pr-review-loop.sh
HARNESS_MODE=1 source "$LOOP_SCRIPT"

_head="cccccccccccccccccccccccccccccccccccccccc"
_tmp_dir="$(mktemp -d)"
trap 'rm -rf "${_tmp_dir:-}"' EXIT

_kv() {
  printf '%s\n' "$2" | grep "^${1}=" | head -1 | cut -d= -f2-
}

# Every later gate condition is satisfied, so the only unmet condition is the
# missing local reviewer — the exact shape reported in #1817.
expensive_gate_unresolved_threads_status() { printf 'ok 0 %s\n' "$_head"; }
expensive_gate_baseline_checks_status() { printf 'green %s\n' "$_head"; }

_ledger_with_deferrals() {
  local n="$1" i _ledger_json="["
  for i in $(seq 1 "$n"); do
    [ "$i" -gt 1 ] && _ledger_json+=","
    _ledger_json+="{\"result\":\"needs_fixes\",\"reason\":\"expensive_gate_deferred\",\"head_sha\":\"$_head\",\"expensive_gate\":{\"platform\":\"codex-github\",\"result\":\"deferred\",\"reason\":\"baseline_checks_pending\",\"head\":\"$_head\"}}"
  done
  _ledger_json+="]"
  printf '%s\n' "<!-- reviewer-loop-history:v1 -->
\`\`\`json
{\"schema\":\"reviewer_loop_history.v1\",\"history_status\":\"available\",\"entries\":${_ledger_json}}
\`\`\`"
}

_reset_gate_inputs() {
  repo_review_platforms=(pr-agent codex-github)
  platforms=(pr-agent codex-github)
  phase_after_clean_platforms=()
  platform_reviewed_heads=()
  platform_peer_evidence=("pr-agent|clean|")
  expensive_gate_max_deferrals=3
  EXPENSIVE_GATE_MOCK_LEDGER_BODY=""
  unset PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS
}

echo "=== test-expensive-gate-config-error (#1817) ==="

# --- 1. Gate unit: missing local reviewer is a configuration error ---
_reset_gate_inputs
_rc=0
_out="$(expensive_reviewer_gate 1817 codex-github "$_head" 2>/dev/null)" || _rc=$?
run_test "1817_gate_result_config_error" "config_error" "$(_kv EXPENSIVE_GATE_RESULT "$_out")"
run_test "1817_gate_reason" "local_reviewer_not_configured" "$(_kv EXPENSIVE_GATE_REASON "$_out")"
run_test "1817_gate_escalation" "expensive_gate_local_reviewer_not_configured" \
  "$(_kv EXPENSIVE_GATE_ESCALATION "$_out")"
run_test "1817_gate_rc_refuses" "1" "$_rc"
run_test "1817_gate_no_deferred_result" "0" \
  "$(printf '%s\n' "$_out" | grep -c '^EXPENSIVE_GATE_RESULT=deferred$' || true)"

# The configuration error wins over the deferral budget: it is reported the
# same way with no prior deferrals and with an exhausted budget.
_reset_gate_inputs
EXPENSIVE_GATE_MOCK_LEDGER_BODY="$(_ledger_with_deferrals 3)"
_out="$(expensive_reviewer_gate 1817 codex-github "$_head" 2>/dev/null)" || true
run_test "1817_gate_config_error_beats_cap" "config_error" "$(_kv EXPENSIVE_GATE_RESULT "$_out")"
run_test "1817_gate_config_error_beats_cap_escalation" "expensive_gate_local_reviewer_not_configured" \
  "$(_kv EXPENSIVE_GATE_ESCALATION "$_out")"

# A config_error entry in the ledger is not a deferral, so it never spends the
# head-scoped deferral budget.
EXPENSIVE_GATE_MOCK_LEDGER_BODY="<!-- reviewer-loop-history:v1 -->
\`\`\`json
{\"schema\":\"reviewer_loop_history.v1\",\"history_status\":\"available\",\"entries\":[{\"result\":\"escalate\",\"reason\":\"expensive_gate_local_reviewer_not_configured\",\"head_sha\":\"$_head\",\"expensive_gate\":{\"platform\":\"codex-github\",\"result\":\"config_error\",\"reason\":\"local_reviewer_not_configured\",\"head\":\"$_head\"}}]}
\`\`\`"
run_test "1817_ledger_config_error_not_counted" "0" "$(expensive_gate_deferral_count "$_head")"

# --- 2. The explicit force override is unchanged ---
_reset_gate_inputs
export PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS=1
_rc=0
_out="$(expensive_reviewer_gate 1817 codex-github "$_head" 2>/dev/null)" || _rc=$?
run_test "1817_force_result" "forced" "$(_kv EXPENSIVE_GATE_RESULT "$_out")"
run_test "1817_force_reason_preserved" "local_reviewer_not_configured" "$(_kv EXPENSIVE_GATE_REASON "$_out")"
run_test "1817_force_rc0" "0" "$_rc"
unset PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS

# --- 3. Configured local reviewer keeps the ordinary deferral path ---
_reset_gate_inputs
repo_review_platforms=(local-ai-reviewer pr-agent codex-github)
platforms=(local-ai-reviewer pr-agent codex-github)
platform_reviewed_heads=("local-ai-reviewer:dddddddddddddddddddddddddddddddddddddddd")
platform_peer_evidence=("local-ai-reviewer|clean|" "pr-agent|clean|")
_out="$(expensive_reviewer_gate 1817 codex-github "$_head" 2>/dev/null)" || true
run_test "1817_configured_stale_still_defers" "deferred" "$(_kv EXPENSIVE_GATE_RESULT "$_out")"
run_test "1817_configured_stale_no_escalation" "" "$(_kv EXPENSIVE_GATE_ESCALATION "$_out")"

# --- 4. Real loop body: draft-phase and ready-phase paths escalate at once ---
# Extract the production platform loop so the assertions exercise its actual
# routing (the per-platform pre-dispatch and the ready-phase preflight that runs
# before `gh pr ready`) instead of restating it.
_loop_body="$(awk '
  index($0, "for index in \"${!platforms[@]}\"; do") == 1 { on = 1 }
  on && index($0, "# --- Automated Reviewer Loop Summary comment ---") == 1 { exit }
  on { print }
' "$LOOP_SCRIPT")"
run_test "1817_loop_body_extracted" "1" \
  "$(printf '%s\n' "$_loop_body" | grep -c 'reviewer_loop_platform_pre_dispatch "\$platform_name" "\$platform_index"' || true)"

_ran_file="$_tmp_dir/ran"
_ready_file="$_tmp_dir/ready"
run_platform_review() {
  printf '%s\n' "$1" >> "$_ran_file"
  printf 'RESULT=clean\nREASON=\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n'
}
ensure_pr_ready_for_ready_phase() { printf 'ready\n' >> "$_ready_file"; return 0; }
reviewer_loop_second_local_pass_before_ready_gate() { return 0; }
reviewer_loop_prior_history_payload_from_pr() { printf '{"entries":[]}\n'; }
reviewer_loop_second_local_pass_confirm_live_head() { return 0; }
reviewer_wait_budget_for_platform() { printf '1 synthetic unchanged\n'; }
reviewer_poll_interval_resolve() { printf '1\n'; }
reviewer_loop_rewait_prepare_platform() { :; }
reviewer_loop_head_refs_prepare_platform() { :; }
reviewer_loop_timing_begin() { :; }
reviewer_loop_timing_end() { :; }
reviewer_loop_process_platform_output() {
  last_platform="$1"
  platform_peer_evidence+=("${1}|clean|")
}

_reset_loop_state() {
  : > "$_ran_file"
  : > "$_ready_file"
  _reset_gate_inputs
  stage_skip_enabled=0
  stage_skip_history_payload=""
  stage_skipped_platforms=()
  reviewer_loop_pre_dispatch_action="dispatch"
  reviewer_loop_gate_break_result=""
  phase_after_clean_enabled=0
  phase_after_clean_started=0
  compare_mode=0
  compare_first_blocking_result=""
  compare_verdicts=()
  loop_head_sha="$_head"
  pr_number=1817
  branch_name="fix/1817-fixture"
  aggregate_result="skipped"
  aggregate_reason=""
  aggregate_output=""
  aggregate_status=0
  last_platform=""
  platform_result_records=()
  platform_result_tokens=()
  local_retry_preparation_failed=0
  expensive_gate_last_platform=""
  expensive_gate_last_result=""
  expensive_gate_last_reason=""
  expensive_gate_last_head=""
}

_run_loop() {
  set +e
  eval "$_loop_body" > "$_tmp_dir/loop.out" 2>/dev/null
  set -e
}

# 4a. Draft phase: codex-github listed in on_draft.github next to pr-agent.
_reset_loop_state
_run_loop
run_test "1817_draft_aggregate_escalate" "escalate" "$aggregate_result"
run_test "1817_draft_reason" "expensive_gate_local_reviewer_not_configured" "$aggregate_reason"
run_test "1817_draft_status" "2" "$aggregate_status"
run_test "1817_draft_output_reason" "expensive_gate_local_reviewer_not_configured" \
  "$(_kv REASON "$aggregate_output")"
run_test "1817_draft_output_zero_blocking" "0" "$(_kv BLOCKING_COUNT "$aggregate_output")"
run_test "1817_draft_codex_not_dispatched" "0" "$(grep -c '^codex-github$' "$_ran_file" || true)"
run_test "1817_draft_peer_ran" "1" "$(grep -c '^pr-agent$' "$_ran_file" || true)"
run_test "1817_draft_token" "codex-github:config_error (local_reviewer_not_configured)" \
  "${platform_result_tokens[*]:-}"
run_test "1817_draft_last_result" "config_error" "$expensive_gate_last_result"
run_contains "1817_draft_telemetry" "EXPENSIVE_GATE_RESULT=config_error" "$_tmp_dir/loop.out"
run_test "1817_draft_reviewer_failed_label" "required" \
  "$(reviewer_failed_label_required_for_result "$aggregate_result" "$aggregate_reason" && echo required || echo not_required)"

# 4b. Ready phase: on_ready.github: [codex-github] with no local reviewer — the
# configuration in the #1817 report. The preflight must escalate before the PR
# is marked ready, so a vendor auto-start cannot fire.
_reset_loop_state
phase_after_clean_platforms=(codex-github)
phase_after_clean_enabled=1
_run_loop
run_test "1817_ready_aggregate_escalate" "escalate" "$aggregate_result"
run_test "1817_ready_reason" "expensive_gate_local_reviewer_not_configured" "$aggregate_reason"
run_test "1817_ready_status" "2" "$aggregate_status"
run_test "1817_ready_not_marked_ready" "0" "$(grep -c '^ready$' "$_ready_file" || true)"
run_test "1817_ready_codex_not_dispatched" "0" "$(grep -c '^codex-github$' "$_ran_file" || true)"
run_test "1817_ready_token" "codex-github:config_error (local_reviewer_not_configured)" \
  "${platform_result_tokens[*]:-}"
run_contains "1817_ready_telemetry" "EXPENSIVE_GATE_ESCALATION=expensive_gate_local_reviewer_not_configured" \
  "$_tmp_dir/loop.out"

# 4c. Ready phase with force: the gate yields to the explicit override, the PR
# is marked ready and codex-github is dispatched.
_reset_loop_state
phase_after_clean_platforms=(codex-github)
phase_after_clean_enabled=1
export PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS=1
_run_loop
unset PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS
run_test "1817_ready_forced_marked_ready" "1" "$(grep -c '^ready$' "$_ready_file" || true)"
run_test "1817_ready_forced_dispatched" "1" "$(grep -c '^codex-github$' "$_ran_file" || true)"

# --- 5. Documentation names the new outcome at every config surface ---
_p93="$REPO_ROOT/docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md"
_cg="$REPO_ROOT/docs/workflow/development-workflow/integrations/codex-github.md"
_prp="$REPO_ROOT/docs/workflow/development-workflow/integrations/pr-review-platform.md"
for _doc in "$_p93" "$_cg" "$_prp"; do
  _name="$(basename "$_doc" .md)"
  run_contains "1817_docs_${_name}_reason" "expensive_gate_local_reviewer_not_configured" "$_doc"
  run_contains "1817_docs_${_name}_result" "config_error" "$_doc"
done

echo ""
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
[ "$FAIL_COUNT" -eq 0 ]
