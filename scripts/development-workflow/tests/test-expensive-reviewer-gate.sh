#!/usr/bin/env bash
# test-expensive-reviewer-gate.sh — composition / override scenarios for #1649.
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md
#
# Scenarios 15, 16, 17, 21, 22 from the implementation plan.
# shellcheck shell=bash disable=SC2034
# SC2034: test globals are read by functions sourced from pr-review-loop.sh.

set -euo pipefail
# Globals below are read by functions sourced from pr-review-loop.sh.
# shellcheck disable=SC2034

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

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
  local name="$1" needle="$2" haystack="$3"
  if printf '%s\n' "$haystack" | grep -Fq -- "$needle"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name — expected substring '${needle}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

export MOCK_REPO_ROOT="$REPO_ROOT"
# shellcheck source=scripts/development-workflow/pr-review-loop.sh
HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

_head="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
_other="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

expensive_gate_unresolved_threads_status() {
  printf 'ok 0 %s\n' "${MOCK_THREADS_HEAD:-$_head}"
}
expensive_gate_baseline_checks_status() {
  printf 'green %s\n' "${MOCK_CHECKS_HEAD:-$_head}"
}

_kv() {
  printf '%s\n' "$2" | grep "^${1}=" | head -1 | cut -d= -f2-
}

echo "=== test-expensive-reviewer-gate (#1649) ==="

# --- Scenario 15: force override ---
platforms=(local-ai-reviewer pr-agent codex-github)
phase_after_clean_platforms=()
platform_reviewed_heads=("local-ai-reviewer:$_other")
platform_peer_evidence=("local-ai-reviewer|clean|" "pr-agent|clean|")
expensive_gate_max_deferrals=3
EXPENSIVE_GATE_MOCK_LEDGER_BODY=""
export PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS=1
_out="$(expensive_reviewer_gate 42 codex-github "$_head" 2>/dev/null)" || _rc=$?
_rc="${_rc:-0}"
run_test "1649_s15_forced" "forced" "$(_kv EXPENSIVE_GATE_RESULT "$_out")"
run_test "1649_s15_reason_preserved" "local_evidence_stale" "$(_kv EXPENSIVE_GATE_REASON "$_out")"
run_test "1649_s15_rc0" "0" "$_rc"
unset PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS
unset _rc

# --- Scenario 22: in-loop derivation matches LOCAL_AI_* producer ---
# Case A: configured + current head
platforms=(local-ai-reviewer pr-agent)
platform_reviewed_heads=("local-ai-reviewer:$_head")
loop_head_sha="$_head"
_cfg="$(expensive_gate_local_ai_configured)"
_hc="$(expensive_gate_local_ai_head_current "$_head")"
# Simulate producer (same logic as reviewer_loop_emit_local_ai_head_evidence_keys)
_prod_cfg=0
for p in "${platforms[@]}"; do
  [ "$p" = "local-ai-reviewer" ] && _prod_cfg=1
done
_prod_hc=""
for entry in "${platform_reviewed_heads[@]}"; do
  if [ "${entry%%:*}" = "local-ai-reviewer" ]; then
    classification="$(reviewer_loop_head_evidence_classify "${entry#*:}" "$loop_head_sha")"
    state="${classification%%|*}"
    case "$state" in
      current) _prod_hc=1 ;;
      not-current) _prod_hc=0 ;;
      *) _prod_hc="" ;;
    esac
  fi
done
run_test "1649_s22_current_match" "${_prod_cfg}|${_prod_hc}" "${_cfg}|${_hc}"

# Case B: stale
platform_reviewed_heads=("local-ai-reviewer:$_other")
_cfg="$(expensive_gate_local_ai_configured)"
_hc="$(expensive_gate_local_ai_head_current "$_head")"
run_test "1649_s22_stale" "1|0" "${_cfg}|${_hc}"

# Case C: unreported (empty reviewed head)
platform_reviewed_heads=("local-ai-reviewer:")
_cfg="$(expensive_gate_local_ai_configured)"
_hc="$(expensive_gate_local_ai_head_current "$_head")"
run_test "1649_s22_unreported" "1|" "${_cfg}|${_hc}"

# Case D: not configured
platforms=(pr-agent)
platform_reviewed_heads=()
_cfg="$(expensive_gate_local_ai_configured)"
_hc="$(expensive_gate_local_ai_head_current "$_head")"
run_test "1649_s22_not_configured" "0|" "${_cfg}|${_hc}"

# --- Scenario 16: phase then gate (composition with ensure_pr_ready) ---
_call_order=()
ensure_pr_ready_for_ready_phase() {
  _call_order+=("ready_phase")
  return 0
}
platform_name="codex-github"
phase_after_clean_platforms=(codex-github)
phase_after_clean_enabled=1
phase_after_clean_started=0
compare_mode=0
platforms=(local-ai-reviewer codex-github)
platform_reviewed_heads=("local-ai-reviewer:$_head")
platform_peer_evidence=("local-ai-reviewer|clean|")
loop_head_sha="$_head"
_call_order=()
if [ "$phase_after_clean_enabled" -eq 1 ] \
    && [ "$phase_after_clean_started" -eq 0 ] \
    && is_phase_after_clean_platform "$platform_name"; then
  ensure_pr_ready_for_ready_phase 99 || true
  phase_after_clean_started=1
  _call_order+=("phase_done")
fi
if is_expensive_reviewer_platform "$platform_name"; then
  platform_reviewed_heads=("local-ai-reviewer:$_other")
  expensive_reviewer_gate 99 "$platform_name" "$loop_head_sha" >/dev/null || true
  _call_order+=("gate")
fi
run_test "1649_s16_phase_before_gate" "ready_phase phase_done gate" "${_call_order[*]}"
run_test "1649_s16_phase_started" "1" "${phase_after_clean_started:-unset}"

# --- Scenario 17: --pre-after-clean-only filters phase expensive before gate ---
platforms=(local-ai-reviewer codex-github)
phase_after_clean_platforms=(codex-github)
phase_after_clean_started=0
filter_pre_after_clean_platforms
_gate_called=0
# Do not shadow expensive_reviewer_gate (hard to restore). Instead assert
# codex-github was removed from platforms so the gate would never be consulted.
run_test "1649_s17_codex_filtered_out" "local-ai-reviewer" \
  "$(IFS=,; printf '%s' "${platforms[*]}")"
run_test "1649_s17_codex_not_in_list" "1" \
  "$(is_expensive_reviewer_platform codex-github && array_contains_value codex-github "${platforms[@]:-}" && echo 0 || echo 1)"

# --- Scenario 21: draft-phase defer does not start ready phase ---
_ready_called=0
ensure_pr_ready_for_ready_phase() { _ready_called=1; return 0; }
_run_platform_called=()
phase_after_clean_started=0
platforms=(local-ai-reviewer pr-agent codex-github bugbot)
phase_after_clean_platforms=(bugbot)
reorder_expensive_reviewers_last
platform_peer_evidence=()
platform_reviewed_heads=("local-ai-reviewer:$_head")
expensive_gate_max_deferrals=3
EXPENSIVE_GATE_MOCK_LEDGER_BODY=""
loop_head_sha="$_head"
aggregate_result="skipped"
# Force defer by clearing peers after local-ai "runs", then hitting gate with
# stale local evidence before bugbot.
for platform_name in "${platforms[@]}"; do
  if is_phase_after_clean_platform "$platform_name" && [ "${phase_after_clean_started:-0}" -eq 0 ]; then
    ensure_pr_ready_for_ready_phase 1
    phase_after_clean_started=1
  fi
  if is_expensive_reviewer_platform "$platform_name"; then
    platform_reviewed_heads=("local-ai-reviewer:$_other")
    if ! expensive_reviewer_gate 21 "$platform_name" "$_head" >/dev/null; then
      aggregate_result="needs_fixes"
      break
    fi
  fi
  _run_platform_called+=("$platform_name")
  platform_peer_evidence+=("${platform_name}|clean|")
done
run_test "1649_s21_ready_not_called" "0" "${_ready_called}"
run_test "1649_s21_bugbot_not_run" "0" \
  "$(printf '%s\n' "${_run_platform_called[@]:-}" | grep -c '^bugbot$' || true)"
run_test "1649_s21_aggregate_needs_fixes" "needs_fixes" "$aggregate_result"
run_contains "1649_s21_no_bugbot_in_ran" "local-ai-reviewer" \
  "$(IFS=,; printf '%s' "${_run_platform_called[*]}")"

# Docs parity: both docs mention both escalation values
_p93="$REPO_ROOT/docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md"
_cg="$REPO_ROOT/docs/workflow/development-workflow/integrations/codex-github.md"
run_contains "1649_docs_p93_cap" "expensive_gate_deferral_cap" "$(cat "$_p93")"
run_contains "1649_docs_p93_unreadable" "expensive_gate_deferral_budget_unreadable" "$(cat "$_p93")"
run_contains "1649_docs_cg_cap" "expensive_gate_deferral_cap" "$(cat "$_cg")"
run_contains "1649_docs_cg_unreadable" "expensive_gate_deferral_budget_unreadable" "$(cat "$_cg")"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
