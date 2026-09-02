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

# --- Scenario 23: ready-phase preflight — gate before gh pr ready ---
# When the first ready-phase platform is non-expensive (bugbot) but a later
# ready-phase platform is expensive (codex-github), a deferring expensive gate
# must prevent ensure_pr_ready_for_ready_phase so auto-trigger cannot start.
_ready_called=0
ensure_pr_ready_for_ready_phase() { _ready_called=$((_ready_called + 1)); return 0; }
_run_platform_called=()
run_platform_review() { _run_platform_called+=("$1"); printf 'RESULT=clean\nREASON=\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n'; return 0; }
phase_after_clean_started=0
phase_after_clean_enabled=1
compare_mode=0
compare_first_blocking_result=""
platforms=(local-ai-reviewer bugbot codex-github)
phase_after_clean_platforms=(bugbot codex-github)
reorder_expensive_reviewers_last
platform_peer_evidence=("local-ai-reviewer|clean|")
platform_reviewed_heads=("local-ai-reviewer:$_other")
expensive_gate_max_deferrals=3
EXPENSIVE_GATE_MOCK_LEDGER_BODY=""
loop_head_sha="$_head"
pr_number=23
aggregate_result="skipped"
aggregate_reason=""
aggregate_status=0
platform_result_tokens=()
# Mirror the production ready-phase entry + expensive preflight + per-platform gate.
for index in "${!platforms[@]}"; do
  platform_name="${platforms[$index]}"
  if [ "$phase_after_clean_enabled" -eq 1 ] \
      && [ "$phase_after_clean_started" -eq 0 ] \
      && is_phase_after_clean_platform "$platform_name"; then
    _eg_ready_preflight_failed=0
    for ((_eg_i = index; _eg_i < ${#platforms[@]}; _eg_i++)); do
      _eg_plat="${platforms[$_eg_i]}"
      if ! is_phase_after_clean_platform "$_eg_plat"; then
        continue
      fi
      if ! is_expensive_reviewer_platform "$_eg_plat"; then
        continue
      fi
      if ! expensive_reviewer_gate "$pr_number" "$_eg_plat" "$loop_head_sha" "earlier_buckets" >/dev/null; then
        aggregate_result="needs_fixes"
        aggregate_reason="expensive_gate_deferred"
        _eg_ready_preflight_failed=1
        break
      fi
    done
    if [ "$_eg_ready_preflight_failed" -eq 1 ]; then
      break
    fi
    ensure_pr_ready_for_ready_phase "$pr_number"
    phase_after_clean_started=1
  fi
  if is_expensive_reviewer_platform "$platform_name"; then
    if ! expensive_reviewer_gate "$pr_number" "$platform_name" "$loop_head_sha" >/dev/null; then
      aggregate_result="needs_fixes"
      break
    fi
  fi
  _run_platform_called+=("$platform_name")
done
run_test "1649_s23_ready_not_called" "0" "$_ready_called"
run_test "1649_s23_aggregate_needs_fixes" "needs_fixes" "$aggregate_result"
run_test "1649_s23_bugbot_not_run" "0" \
  "$(printf '%s\n' "${_run_platform_called[@]:-}" | grep -c '^bugbot$' || true)"

# --- Scenario 24: earlier_buckets preflight does not deadlock on bugbot ---
# Full peer scope would require bugbot before ready; earlier_buckets must not.
platforms=(local-ai-reviewer bugbot codex-github)
phase_after_clean_platforms=(bugbot codex-github)
reorder_expensive_reviewers_last
platform_peer_evidence=("local-ai-reviewer|clean|")
platform_reviewed_heads=("local-ai-reviewer:$_head")
expensive_gate_unresolved_threads_status() { printf 'ok 0 %s\n' "$_head"; }
expensive_gate_baseline_checks_status() { printf 'green %s\n' "$_head"; }
expensive_gate_max_deferrals=3
EXPENSIVE_GATE_MOCK_LEDGER_BODY=""
_out="$(expensive_reviewer_gate 24 codex-github "$_head" "earlier_buckets" 2>/dev/null)" || true
run_test "1649_s24_preflight_dispatched" "dispatched" \
  "$(printf '%s\n' "$_out" | grep '^EXPENSIVE_GATE_RESULT=' | head -1 | cut -d= -f2-)"
_out_full="$(expensive_reviewer_gate 24 codex-github "$_head" "full" 2>/dev/null)" || true
run_test "1649_s24_full_waits_on_bugbot" "peer_reviewer_not_run" \
  "$(printf '%s\n' "$_out_full" | grep '^EXPENSIVE_GATE_REASON=' | head -1 | cut -d= -f2-)"
_ready_called=0
ensure_pr_ready_for_ready_phase() { _ready_called=$((_ready_called + 1)); return 0; }
phase_after_clean_started=0
phase_after_clean_enabled=1
loop_head_sha="$_head"
pr_number=24
aggregate_result="skipped"
for index in "${!platforms[@]}"; do
  platform_name="${platforms[$index]}"
  if [ "$phase_after_clean_enabled" -eq 1 ] \
      && [ "$phase_after_clean_started" -eq 0 ] \
      && is_phase_after_clean_platform "$platform_name"; then
    _eg_ready_preflight_failed=0
    for ((_eg_i = index; _eg_i < ${#platforms[@]}; _eg_i++)); do
      _eg_plat="${platforms[$_eg_i]}"
      if is_phase_after_clean_platform "$_eg_plat" && is_expensive_reviewer_platform "$_eg_plat"; then
        if ! expensive_reviewer_gate "$pr_number" "$_eg_plat" "$loop_head_sha" "earlier_buckets" >/dev/null; then
          _eg_ready_preflight_failed=1
          aggregate_result="needs_fixes"
          break
        fi
      fi
    done
    if [ "$_eg_ready_preflight_failed" -eq 1 ]; then
      break
    fi
    ensure_pr_ready_for_ready_phase "$pr_number"
    phase_after_clean_started=1
    break
  fi
done
run_test "1649_s24_ready_called" "1" "$_ready_called"
run_test "1649_s24_not_deferred" "skipped" "$aggregate_result"

# --- Scenario 25: command-substitution must rehydrate expensive_gate_last_* ---
platforms=(local-ai-reviewer pr-agent codex-github)
phase_after_clean_platforms=()
platform_peer_evidence=("local-ai-reviewer|clean|" "pr-agent|clean|")
platform_reviewed_heads=("local-ai-reviewer:$_other")
expensive_gate_unresolved_threads_status() { printf 'ok 0 %s\n' "$_head"; }
expensive_gate_baseline_checks_status() { printf 'green %s\n' "$_head"; }
expensive_gate_max_deferrals=3
EXPENSIVE_GATE_MOCK_LEDGER_BODY=""
expensive_gate_last_result=""
expensive_gate_last_reason=""
_out="$(expensive_reviewer_gate 25 codex-github "$_head" 2>/dev/null)" || true
run_test "1649_s25_subshell_loses_globals" "" "${expensive_gate_last_result:-}"
expensive_gate_sync_last_from_output "$_out"
run_test "1649_s25_sync_restores_result" "deferred" "${expensive_gate_last_result:-}"
run_test "1649_s25_sync_restores_reason" "local_evidence_stale" "${expensive_gate_last_reason:-}"

# Docs parity: both docs mention both escalation values + ready-phase preflight.
# Grep files directly — do not $(cat) Protocol 93 into argv (ARG_MAX).
_p93="$REPO_ROOT/docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md"
_cg="$REPO_ROOT/docs/workflow/development-workflow/integrations/codex-github.md"
_docs_has() {
  local name="$1" needle="$2" file="$3"
  if grep -Fq -- "$needle" "$file"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name — expected substring '${needle}' in ${file}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}
_docs_has "1649_s23_docs_p93_preflight" "preflight" "$_p93"
_docs_has "1649_s23_docs_cg_preflight" "preflight" "$_cg"
_docs_has "1649_docs_p93_cap" "expensive_gate_deferral_cap" "$_p93"
_docs_has "1649_docs_p93_unreadable" "expensive_gate_deferral_budget_unreadable" "$_p93"
_docs_has "1649_docs_cg_cap" "expensive_gate_deferral_cap" "$_cg"
_docs_has "1649_docs_cg_unreadable" "expensive_gate_deferral_budget_unreadable" "$_cg"

# --- Scenario 1692: per-head replay never bypasses the expensive gate ---
# A recorded clean vouches for one reviewer's verdict on one commit. It does not
# vouch for the gate's LIVE inputs — unresolved review threads and baseline
# check runs on that same head, which can change after the verdict was
# recorded. So an expensive reviewer with a clean ledger entry for the current
# head must still clear its gate before anything reports clean for it.
_1692_head="$_head"
_1692_ledger_clean="$(jq -nc --arg head "$_1692_head" '{
  schema: "reviewer_loop_history.v1",
  entries: [{
    iteration: 1,
    platform_results: [{platform: "codex-github", result: "clean", raw_result: "clean", raw_reason: ""}],
    reviewed_heads: [{platform: "codex-github", reviewed_head: $head, state: "current", reason: ""}]
  }]
}')"
run_test "1692_gate_ledger_says_clean_current" "clean_current" \
  "$(reviewer_loop_platform_clean_for_head "$_1692_ledger_clean" codex-github "$_1692_head")"

# The ordering predicate: an expensive reviewer owes its gate; nothing else does.
run_test "1692_gate_expensive_pending_refused" "refused" \
  "$(reviewer_loop_stage_skip_allowed_now codex-github pending && echo allowed || echo refused)"
run_test "1692_gate_expensive_not_required_refused" "refused" \
  "$(reviewer_loop_stage_skip_allowed_now codex-github not_required && echo allowed || echo refused)"
run_test "1692_gate_expensive_passed_allowed" "allowed" \
  "$(reviewer_loop_stage_skip_allowed_now codex-github passed && echo allowed || echo refused)"
run_test "1692_gate_cheap_not_required_allowed" "allowed" \
  "$(reviewer_loop_stage_skip_allowed_now local-ai-reviewer not_required && echo allowed || echo refused)"
run_test "1692_gate_cheap_passed_allowed" "allowed" \
  "$(reviewer_loop_stage_skip_allowed_now local-ai-reviewer passed && echo allowed || echo refused)"
run_test "1692_gate_cheap_unknown_state_refused" "refused" \
  "$(reviewer_loop_stage_skip_allowed_now local-ai-reviewer pending && echo allowed || echo refused)"

# Composition through the REAL loop body. reviewer_loop_platform_pre_dispatch is
# the function the platform loop calls, so these assertions fail if the ordering
# or the telemetry suppression regresses in production code — they do not restate
# it in the harness.
_1692_ran=()
# reviewer_loop_platform_pre_dispatch sets loop globals, so it must run in this
# shell — capturing it with $( ) would run it in a subshell and lose every
# assignment (the same trap expensive_gate_sync_last_from_output documents).
_1692_tmp="$(mktemp)"
trap 'rm -f "${_1692_tmp:-}"' EXIT
run_platform_review() { _1692_ran+=("$1"); printf 'RESULT=clean\nREASON=\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n'; return 0; }
_1692_reset() {
  _1692_ran=()
  stage_skip_enabled=1
  stage_skip_history_payload="$_1692_ledger_clean"
  stage_skipped_platforms=()
  reviewer_loop_pre_dispatch_action=""
  platforms=(local-ai-reviewer codex-github)
  repo_review_platforms=(local-ai-reviewer codex-github)
  phase_after_clean_platforms=()
  phase_after_clean_enabled=0
  phase_after_clean_started=0
  compare_mode=0
  compare_verdicts=()
  loop_head_sha="$_1692_head"
  pr_number=1692
  expensive_gate_max_deferrals=3
  EXPENSIVE_GATE_MOCK_LEDGER_BODY=""
  aggregate_result="skipped"
  aggregate_reason=""
  aggregate_output=""
  aggregate_status=0
  aggregate_advisory_labels=""
  total_comment_count=0
  total_blocking_count=0
  total_suggestion_count=0
  reviewer_failed_required=0
  last_platform=""
  platform_peer_evidence=("local-ai-reviewer|clean|")
  platform_result_records=()
  platform_result_tokens=()
  platform_blocking_outputs=()
  platform_policy_status_notes=()
  aggregate_blocking_paths=()
  aggregate_blocking_findings=()
  reviewer_loop_platform_loop_should_break=0
  expensive_gate_last_platform=""
  expensive_gate_last_result=""
  expensive_gate_last_reason=""
  expensive_gate_last_head=""
  # Fresh local evidence by default; the deferring case overrides it.
  platform_reviewed_heads=("local-ai-reviewer:$_1692_head")
}

# Case 1 — ledger says clean on this head, but the gate defers on stale live
# local evidence. No replay, no dispatch, deferral reported.
_1692_reset
platform_reviewed_heads=("local-ai-reviewer:$_other")
reviewer_loop_platform_pre_dispatch codex-github 1 >"$_1692_tmp" 2>/dev/null
_1692_out="$(cat "$_1692_tmp")"
run_test "1692_gate_defer_action" "break" "$reviewer_loop_pre_dispatch_action"
run_test "1692_gate_defer_no_replay" "0" \
  "$(printf '%s\n' "${stage_skipped_platforms[@]:-}" | grep -c '^codex-github$' || true)"
run_test "1692_gate_defer_no_dispatch" "0" \
  "$(printf '%s\n' "${_1692_ran[@]:-}" | grep -c '^codex-github$' || true)"
run_test "1692_gate_defer_aggregate" "needs_fixes" "$aggregate_result"
run_test "1692_gate_defer_reason" "expensive_gate_deferred" "$aggregate_reason"
run_contains "1692_gate_defer_emits_gate_telemetry" "EXPENSIVE_GATE_RESULT=deferred" "$_1692_out"

# Case 2 — same ledger, same head, gate passes. The replay fires, nothing is
# dispatched, and the passing gate emits no dispatched/forced telemetry and
# leaves no expensive_gate_last_* state behind for the summary or the ledger.
_1692_reset
reviewer_loop_platform_pre_dispatch codex-github 1 >"$_1692_tmp" 2>/dev/null
_1692_out="$(cat "$_1692_tmp")"
run_test "1692_gate_pass_action" "replay" "$reviewer_loop_pre_dispatch_action"
run_test "1692_gate_pass_replays" "1" \
  "$(printf '%s\n' "${stage_skipped_platforms[@]:-}" | grep -c '^codex-github$' || true)"
run_test "1692_gate_pass_no_dispatch" "0" \
  "$(printf '%s\n' "${_1692_ran[@]:-}" | grep -c '^codex-github$' || true)"
run_test "1692_gate_pass_no_gate_telemetry" "0" \
  "$(printf '%s\n' "$_1692_out" | grep -c '^EXPENSIVE_GATE_RESULT=' || true)"
run_test "1692_gate_pass_last_result_cleared" "" "$expensive_gate_last_result"
run_test "1692_gate_pass_last_platform_cleared" "" "$expensive_gate_last_platform"
run_test "1692_gate_pass_reviewed_head_recorded" "codex-github:${_1692_head}" \
  "$(printf '%s\n' "${platform_reviewed_heads[@]}" | grep '^codex-github:' || true)"
run_test "1692_gate_pass_peer_evidence" "clean|already_clean_current_head" \
  "$(expensive_gate_lookup_peer_evidence codex-github)"

# Case 3 — gate passes, ledger has no evidence: the reviewer is dispatched and
# the gate telemetry IS emitted, because this run really is a dispatch.
_1692_reset
stage_skip_history_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
reviewer_loop_platform_pre_dispatch codex-github 1 >"$_1692_tmp" 2>/dev/null
_1692_out="$(cat "$_1692_tmp")"
run_test "1692_gate_pass_no_evidence_action" "dispatch" "$reviewer_loop_pre_dispatch_action"
run_contains "1692_gate_pass_no_evidence_emits_telemetry" "EXPENSIVE_GATE_RESULT=" "$_1692_out"

# Case 4 — a non-expensive reviewer has no gate to owe: clean ledger evidence
# replays directly.
_1692_reset
stage_skip_history_payload="$(jq -nc --arg head "$_1692_head" '{
  schema: "reviewer_loop_history.v1",
  entries: [{
    iteration: 1,
    platform_results: [{platform: "local-ai-reviewer", result: "clean", raw_result: "clean", raw_reason: ""}],
    reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $head, state: "current", reason: ""}]
  }]
}')"
reviewer_loop_platform_pre_dispatch local-ai-reviewer 1 >/dev/null 2>&1
run_test "1692_cheap_replays" "replay" "$reviewer_loop_pre_dispatch_action"

# Case 5 — staging disabled: everything dispatches, gate telemetry emitted.
_1692_reset
stage_skip_enabled=0
reviewer_loop_platform_pre_dispatch codex-github 1 >"$_1692_tmp" 2>/dev/null
_1692_out="$(cat "$_1692_tmp")"
run_test "1692_disabled_dispatches" "dispatch" "$reviewer_loop_pre_dispatch_action"
run_contains "1692_disabled_emits_telemetry" "EXPENSIVE_GATE_RESULT=" "$_1692_out"

# Planted-violation proofs: the wrong orderings live only in this harness, and
# the assertions above are what separates them from the shipped function.
#
# PV1 — act on the replay before the gate (the original #1692 defect): a stale
# live-evidence state that must defer instead replays clean.
_1692_pv_replay_before_gate() {
  local platform_name="$1" platform_index="$2"
  reviewer_loop_pre_dispatch_action="dispatch"
  if [ "$stage_skip_enabled" -eq 1 ] \
      && [ "$(reviewer_loop_platform_clean_for_head "$stage_skip_history_payload" "$platform_name" "$loop_head_sha")" = "clean_current" ]; then
    stage_skipped_platforms+=("$platform_name")
    reviewer_loop_pre_dispatch_action="replay"
    return 0
  fi
  if is_expensive_reviewer_platform "$platform_name"; then
    expensive_reviewer_gate "$pr_number" "$platform_name" "$loop_head_sha" >/dev/null 2>&1 \
      || { reviewer_loop_pre_dispatch_action="break"; return 0; }
  fi
  return 0
}
_1692_reset
platform_reviewed_heads=("local-ai-reviewer:$_other")
_1692_pv_replay_before_gate codex-github 1 >/dev/null 2>&1
run_test "1692_pv1_plant_replays" "replay" "$reviewer_loop_pre_dispatch_action"
_1692_reset
platform_reviewed_heads=("local-ai-reviewer:$_other")
reviewer_loop_platform_pre_dispatch codex-github 1 >/dev/null 2>&1
run_test "1692_pv1_correct_breaks" "break" "$reviewer_loop_pre_dispatch_action"

# PV2 — emit the gate telemetry unconditionally, before the replay branch. The
# stdout contract then reports a dispatch that never happened.
_1692_pv_emit_before_replay() {
  local platform_name="$1" out
  reviewer_loop_pre_dispatch_action="dispatch"
  if is_expensive_reviewer_platform "$platform_name"; then
    out="$(expensive_reviewer_gate "$pr_number" "$platform_name" "$loop_head_sha")" || { reviewer_loop_pre_dispatch_action="break"; printf '%s\n' "$out"; return 0; }
    printf '%s\n' "$out"
  fi
  if [ "$stage_skip_enabled" -eq 1 ] \
      && [ "$(reviewer_loop_platform_clean_for_head "$stage_skip_history_payload" "$platform_name" "$loop_head_sha")" = "clean_current" ]; then
    reviewer_loop_pre_dispatch_action="replay"
  fi
  return 0
}
_1692_reset
_1692_pv_emit_before_replay codex-github >"$_1692_tmp" 2>/dev/null
_1692_out="$(cat "$_1692_tmp")"
run_test "1692_pv2_plant_action" "replay" "$reviewer_loop_pre_dispatch_action"
run_contains "1692_pv2_plant_emits_dispatched" "EXPENSIVE_GATE_RESULT=" "$_1692_out"
_1692_reset
reviewer_loop_platform_pre_dispatch codex-github 1 >"$_1692_tmp" 2>/dev/null
_1692_out="$(cat "$_1692_tmp")"
run_test "1692_pv2_correct_action" "replay" "$reviewer_loop_pre_dispatch_action"
run_test "1692_pv2_correct_suppresses" "0" \
  "$(printf '%s\n' "$_1692_out" | grep -c '^EXPENSIVE_GATE_RESULT=' || true)"

rm -f "$_1692_tmp"
unset _1692_out _1692_tmp
trap - EXIT
unset -f _1692_reset _1692_pv_replay_before_gate _1692_pv_emit_before_replay 2>/dev/null || true

unset _1692_head _1692_ledger_clean _1692_ran
unset -f run_platform_review 2>/dev/null || true

_docs_has "1692_docs_p93_staging" "Per-head reviewer staging" "$_p93"
_docs_has "1692_docs_p93_gate_owner" "#1649" "$_p93"


echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
