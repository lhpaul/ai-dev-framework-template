#!/usr/bin/env bash
# shellcheck disable=SC2034
# test-pr-review-loop-staged-gates.sh — pr-review-loop.sh harness: expensive-
# reviewer gate, strict ledgers, missed-finding telemetry, staged reviewers.
# duration: 10
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
#
# The pr-review-loop.sh harness is split across these suites (#1876), which
# share their preamble — snapshot re-exec, --area filter, gh/git mocks, the
# HARNESS_MODE source of pr-review-loop.sh, and the run_test helpers — through
# tests/lib/pr-review-loop-harness.sh:
#
#   test-pr-review-loop.sh
#   test-pr-review-loop-cycles-labels.sh
#   test-pr-review-loop-failure-paths-1.sh
#   test-pr-review-loop-failure-paths-2.sh
#   test-pr-review-loop-failure-paths-3.sh
#   test-pr-review-loop-failure-paths-4.sh
#   test-pr-review-loop-release-bugbot.sh
#   test-pr-review-loop-pr-agent-coderabbit.sh
#   test-pr-review-loop-staged-gates.sh
#   test-pr-review-loop-no-verdict-yet.sh
#
# Areas in this suite:
#   Area 1649: expensive reviewer gate
#   Area 1650: strict_spec ledger object
#   Area 1655: strict_plan ledger object
#   Area 1651: missed-finding telemetry
#   Area 1653: stage evidence forwarding
#   Area 1656: second local pass
#   Area 1692: per-head reviewer staging
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop-staged-gates.sh [--area <name>]... [--list-areas]
# No external tooling required beyond bash, git, and jq (git only locates the
# repository root at startup; mock gh commands replace all network calls).
#
# Exit code: 0 if all tests pass, 1 if any test fails, 2 on a usage error.
#
# SC2034 is disabled for the whole file (line 2). Most assignments here set
# pr-review-loop.sh globals that the functions under test read; ShellCheck does
# not follow that source, so it sees every one as unused. When the harness was
# a single file the warning stayed quiet only because some other area happened
# to read the same name — coincidence, not analysis.

set -euo pipefail

# Resolve the shared harness from the checked-in suite path. Inside a snapshot
# run $0 is a temp copy, so TEST_PR_REVIEW_LOOP_ORIGIN (set by the harness on
# re-exec, or by hand for an out-of-tree copy) takes precedence.
_prl_harness="$(dirname -- "${TEST_PR_REVIEW_LOOP_ORIGIN:-$0}")/lib/pr-review-loop-harness.sh"
if [ ! -f "$_prl_harness" ]; then
  echo "ERROR: shared harness not found: $_prl_harness" >&2
  echo "  Run the checked-in suite, or set TEST_PR_REVIEW_LOOP_ORIGIN to its path." >&2
  exit 2
fi
# shellcheck source=scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
source "$_prl_harness" "$@"
unset _prl_harness

# Carried state. In the single-file harness, Area 13 exported this for every
# later area; keep the suites that held those areas running under the same
# environment so the split changes where tests live, not what they exercise.
export CODEX_GITHUB_PRE_TRIGGER_WAIT=0

# Carried state: Area 15 (test-pr-review-loop-release-bugbot.sh) left this
# exported for every later area in the single-file harness.
export MOCK_GH_OUTPUT='[]'

# ---------------------------------------------------------------------------
# Area 1649: expensive reviewer gate
# Scenarios 1–14, 14b, 18, 19, 19b (composition/override live in
# test-expensive-reviewer-gate.sh).
# ---------------------------------------------------------------------------
echo "=== Area 1649: expensive reviewer gate ==="

_1649_head="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
_1649_other="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

# --- Scenario 1: is_expensive_reviewer_platform ---
run_test "1649_s1_matches_codex" "0" \
  "$(is_expensive_reviewer_platform codex-github; printf '%s' $?)"
run_test "1649_s1_rejects_local" "1" \
  "$(is_expensive_reviewer_platform local-ai-reviewer; printf '%s' $?)"
run_test "1649_s1_rejects_pr_agent" "1" \
  "$(is_expensive_reviewer_platform pr-agent; printf '%s' $?)"
run_test "1649_s1_rejects_bugbot" "1" \
  "$(is_expensive_reviewer_platform bugbot; printf '%s' $?)"

# --- Scenario 6 / 6b: reorder ---
platforms=(codex-github pr-agent local-ai-reviewer)
phase_after_clean_platforms=()
expensive_reviewers_reordered=0
reorder_expensive_reviewers_last
run_test "1649_s6_moves_codex_last" "pr-agent,local-ai-reviewer,codex-github" \
  "$(IFS=,; printf '%s' "${platforms[*]}")"
run_test "1649_s6_flag_set" "1" "$expensive_reviewers_reordered"

platforms=(pr-agent local-ai-reviewer codex-github)
expensive_reviewers_reordered=0
reorder_expensive_reviewers_last
run_test "1649_s6_already_correct_untouched" "0" "$expensive_reviewers_reordered"

platforms=(codex-github pr-agent local-ai-reviewer bugbot)
phase_after_clean_platforms=(bugbot)
expensive_reviewers_reordered=0
reorder_expensive_reviewers_last
run_test "1649_s6b_phase_bucket" "pr-agent,local-ai-reviewer,codex-github,bugbot" \
  "$(IFS=,; printf '%s' "${platforms[*]}")"
run_test "1649_s6b_codex_before_bugbot" "1" \
  "$(printf '%s\n' "${platforms[@]}" | awk '/codex-github/{c=NR} /bugbot/{b=NR} END{print (c<b)?1:0}')"

# --- Scenario 14b: resolve max deferrals ---
unset PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS
run_test "1649_s14b_unset" "3" "$(expensive_gate_resolve_max_deferrals)"
PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS=
run_test "1649_s14b_empty" "3" "$(expensive_gate_resolve_max_deferrals)"
PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS=1
run_test "1649_s14b_one" "1" "$(expensive_gate_resolve_max_deferrals)"
PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS=999999
run_test "1649_s14b_max" "999999" "$(expensive_gate_resolve_max_deferrals)"
for bad in 0 -1 1000000 abc 2.5 " 2 "; do
  PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS="$bad"
  _warn="$(expensive_gate_resolve_max_deferrals 2>&1 >/dev/null)" || true
  _val="$(PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS="$bad" expensive_gate_resolve_max_deferrals 2>/dev/null)"
  run_test "1649_s14b_reject_${bad// /ws}" "3" "$_val"
  run_contains "1649_s14b_warn_${bad// /ws}" "WARN" "$_warn"
done
unset PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS
expensive_gate_max_deferrals="$(expensive_gate_resolve_max_deferrals)"

# Shared stubs for gate evaluation (conditions 3–4 satisfied unless overridden).
_1649_stub_green_evidence() {
  expensive_gate_unresolved_threads_status() {
    printf 'ok 0 %s\n' "${MOCK_THREADS_HEAD:-$_1649_head}"
  }
  expensive_gate_baseline_checks_status() {
    printf '%s %s\n' "${MOCK_CHECKS_STATE:-green}" "${MOCK_CHECKS_HEAD:-$_1649_head}"
  }
}

_1649_run_gate() {
  local out rc=0
  local pr="${1:-42}"
  local platform="${2:-codex-github}"
  # Allow explicit empty head (scenario 12); only default when unset.
  local head="${3-$_1649_head}"
  if [ "${_1649_preserve_repo_platforms:-0}" -eq 0 ]; then
    repo_review_platforms=("${platforms[@]}")
  fi
  out="$(expensive_reviewer_gate "$pr" "$platform" "$head" 2>/dev/null)" || rc=$?
  printf '%s\n---RC=%s\n' "$out" "$rc"
}

_1649_kv() {
  local key="$1" blob="$2"
  printf '%s\n' "$blob" | grep "^${key}=" | head -1 | cut -d= -f2-
}

# --- Scenario 2: all conditions met → dispatched ---
_1649_stub_green_evidence
platforms=(local-ai-reviewer pr-agent codex-github)
repo_review_platforms=(local-ai-reviewer pr-agent codex-github)
phase_after_clean_platforms=()
platform_reviewed_heads=("local-ai-reviewer:$_1649_head")
platform_peer_evidence=("local-ai-reviewer|clean|" "pr-agent|clean|")
EXPENSIVE_GATE_MOCK_LEDGER_BODY=""
expensive_gate_max_deferrals=3
_out="$(_1649_run_gate)"
run_test "1649_s2_dispatched" "dispatched" "$(_1649_kv EXPENSIVE_GATE_RESULT "$_out")"
run_test "1649_s2_reason_empty" "" "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"
run_test "1649_s2_rc0" "0" "$(grep -E '^---RC=' <<<"$_out" | cut -d= -f2)"

# --- Scenario 3: stale local evidence ---
platform_reviewed_heads=("local-ai-reviewer:$_1649_other")
_out="$(_1649_run_gate)"
run_test "1649_s3_deferred" "deferred" "$(_1649_kv EXPENSIVE_GATE_RESULT "$_out")"
run_test "1649_s3_stale" "local_evidence_stale" "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"
run_test "1649_s3_rc1" "1" "$(grep -E '^---RC=' <<<"$_out" | cut -d= -f2)"

# --- Scenario 4: unexpected / absent local evidence values ---
# Stub configured/head_current helpers directly for allow-list rows.
_orig_cfg="$(declare -f expensive_gate_local_ai_configured)"
_orig_hc="$(declare -f expensive_gate_local_ai_head_current)"
_1649_stub_row() {
  local cfg="$1" hc="$2"
  expensive_gate_local_ai_configured() { printf '%s\n' "$cfg"; }
  expensive_gate_local_ai_head_current() { printf '%s\n' "$hc"; }
  platform_peer_evidence=("local-ai-reviewer|clean|" "pr-agent|clean|")
  platforms=(local-ai-reviewer pr-agent codex-github)
  platform_reviewed_heads=("local-ai-reviewer:$_1649_head")
  _out="$(_1649_run_gate)"
  printf '%s\n' "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"
}
run_test "1649_s4_empty_cfg" "local_evidence_missing" "$(_1649_stub_row "" "1")"
run_test "1649_s4_cfg_2" "local_evidence_missing" "$(_1649_stub_row "2" "1")"
run_test "1649_s4_cfg_true" "local_evidence_missing" "$(_1649_stub_row "true" "1")"
run_test "1649_s4_empty_hc" "local_evidence_missing" "$(_1649_stub_row "1" "")"
run_test "1649_s4_hc_2" "local_evidence_missing" "$(_1649_stub_row "1" "2")"
run_test "1649_s4_hc_yes" "local_evidence_missing" "$(_1649_stub_row "1" "yes")"
eval "$_orig_cfg"
eval "$_orig_hc"

# --- Scenario 5: local reviewer not configured ---
_1649_preserve_repo_platforms=1
platforms=(pr-agent codex-github)
repo_review_platforms=(pr-agent codex-github)
platform_reviewed_heads=()
platform_peer_evidence=("pr-agent|clean|")
_out="$(_1649_run_gate)"
run_test "1649_s5_not_configured" "local_reviewer_not_configured" \
  "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"
unset _1649_preserve_repo_platforms

# Restore for peer scenarios
platforms=(local-ai-reviewer pr-agent codex-github)
platform_reviewed_heads=("local-ai-reviewer:$_1649_head")

# --- Scenario 7: peer set phase-scoped ---
platforms=(local-ai-reviewer pr-agent codex-github bugbot)
phase_after_clean_platforms=(bugbot)
platform_peer_evidence=("local-ai-reviewer|clean|" "pr-agent|clean|")
# bugbot has not run — must still dispatch (not in peer set for draft codex)
_out="$(_1649_run_gate)"
run_test "1649_s7_draft_ignores_ready_peer" "dispatched" \
  "$(_1649_kv EXPENSIVE_GATE_RESULT "$_out")"

# Ready-phase expensive waits on whole draft bucket
platforms=(local-ai-reviewer pr-agent codex-github)
phase_after_clean_platforms=(codex-github)
platform_peer_evidence=("local-ai-reviewer|clean|" "pr-agent|clean|")
_out="$(_1649_run_gate)"
run_test "1649_s7_ready_waits_draft" "dispatched" \
  "$(_1649_kv EXPENSIVE_GATE_RESULT "$_out")"

# Suppressed reorder: peer not run
platforms=(codex-github local-ai-reviewer pr-agent)
phase_after_clean_platforms=()
platform_peer_evidence=()
platform_reviewed_heads=("local-ai-reviewer:$_1649_head")
# Force configured=1 and head current via reviewed heads, but no peers ran
# Condition 1 needs local-ai in platforms AND reviewed head — local-ai is in list
# but hasn't "run" as peer yet; for condition 1 we only need membership + heads.
# Peer set = empty (codex is first) → dispatched on empty peer set?
# Actually peer set is empty when expensive is first → check_peers returns empty → OK for peers.
# The plan says suppressed reorder so a same-bucket peer has not run → deferred peer_reviewer_not_run.
# So we need: list order codex, pr-agent with pr-agent not in peer evidence... wait if codex is first,
# peers before it are empty. The scenario means: after reorder would put codex last, but without
# reorder codex is first and when we get to pr-agent later... Actually when gate runs for codex
# at index 0, peer set is empty so peers pass. The "suppressed reorder" case needs:
# platforms with pr-agent BEFORE codex in the list that the gate sees, but pr-agent not yet in
# platform_peer_evidence — which can't happen in sequential iteration unless we call the gate
# as if somehow out of order. The plan says: "Reorder suppressed so a same-bucket peer has not run"
# So: list is [local-ai, pr-agent, codex] but peer evidence only has local-ai (pr-agent missing).
platforms=(local-ai-reviewer pr-agent codex-github)
platform_peer_evidence=("local-ai-reviewer|clean|")
_out="$(_1649_run_gate)"
run_test "1649_s7_peer_not_run" "peer_reviewer_not_run" \
  "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"

# Local reviewer itself must be clean; accepted skip reasons only apply to
# ordinary peer reviewers.
platforms=(local-ai-reviewer codex-github)
phase_after_clean_platforms=()
platform_reviewed_heads=("local-ai-reviewer:$_1649_head")
platform_peer_evidence=("local-ai-reviewer|skipped|explicit-skip")
_out="$(_1649_run_gate)"
run_test "1649_s7a_local_skip_not_enough" "local_evidence_not_clean" \
  "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"

# --- Scenario 8: peer evidence acceptance ---
_1649_peer_row() {
  local result="$1" reason="$2"
  platforms=(local-ai-reviewer pr-agent codex-github)
  phase_after_clean_platforms=()
  platform_reviewed_heads=("local-ai-reviewer:$_1649_head")
  platform_peer_evidence=("local-ai-reviewer|clean|" "pr-agent|${result}|${reason}")
  _out="$(_1649_run_gate)"
  printf '%s|%s\n' "$(_1649_kv EXPENSIVE_GATE_RESULT "$_out")" "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"
}
run_test "1649_s8_clean" "dispatched|" "$(_1649_peer_row clean "")"
run_test "1649_s8_skip_not_configured" "dispatched|" "$(_1649_peer_row skipped not_configured)"
run_test "1649_s8_skip_explicit" "dispatched|" "$(_1649_peer_row skipped explicit-skip)"
run_test "1649_s8_skip_release" "dispatched|" "$(_1649_peer_row skipped release_pr)"
run_test "1649_s8_skip_unsupported" "dispatched|" "$(_1649_peer_row skipped unsupported-platform)"
run_test "1649_s8_skip_unavailable" "deferred|peer_reviewer_not_clean" "$(_1649_peer_row skipped unavailable)"
run_test "1649_s8_skip_timeout" "deferred|peer_reviewer_not_clean" "$(_1649_peer_row skipped timeout)"
run_test "1649_s8_skip_unauthorized" "deferred|peer_reviewer_not_clean" "$(_1649_peer_row skipped unauthorized)"
run_test "1649_s8_needs_fixes" "deferred|peer_reviewer_not_clean" "$(_1649_peer_row needs_fixes "")"
run_test "1649_s8_escalate" "deferred|peer_reviewer_not_clean" "$(_1649_peer_row escalate "")"
run_test "1649_s8_skip_unknown" "deferred|peer_reviewer_not_clean" "$(_1649_peer_row skipped some_future_reason)"
run_test "1649_s8_skip_empty" "deferred|peer_reviewer_not_clean" "$(_1649_peer_row skipped "")"

# --- Scenario 9: unresolved threads ---
platforms=(local-ai-reviewer pr-agent codex-github)
platform_peer_evidence=("local-ai-reviewer|clean|" "pr-agent|clean|")
platform_reviewed_heads=("local-ai-reviewer:$_1649_head")
expensive_gate_unresolved_threads_status() { printf 'ok 1 %s\n' "$_1649_head"; }
expensive_gate_baseline_checks_status() { printf 'green %s\n' "$_1649_head"; }
_out="$(_1649_run_gate)"
run_test "1649_s9_unresolved" "unresolved_threads" "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"
expensive_gate_unresolved_threads_status() { printf 'ok 0 %s\n' "$_1649_head"; }
_out="$(_1649_run_gate)"
run_test "1649_s9_outdated_ok" "dispatched" "$(_1649_kv EXPENSIVE_GATE_RESULT "$_out")"

# --- Scenario 10: baseline checks ---
_1649_checks_row() {
  local state="$1"
  expensive_gate_unresolved_threads_status() { printf 'ok 0 %s\n' "$_1649_head"; }
  expensive_gate_baseline_checks_status() { printf '%s %s\n' "$state" "$_1649_head"; }
  _out="$(_1649_run_gate)"
  printf '%s|%s\n' "$(_1649_kv EXPENSIVE_GATE_RESULT "$_out")" "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"
}
run_test "1649_s10_failed" "deferred|baseline_checks_not_green" "$(_1649_checks_row failed)"
run_test "1649_s10_pending" "deferred|baseline_checks_pending" "$(_1649_checks_row pending)"
run_test "1649_s10_green" "dispatched|" "$(_1649_checks_row green)"
run_test "1649_s10_empty" "deferred|baseline_checks_unobserved" "$(_1649_checks_row empty)"

# --- Scenario 10 real helper (no stub): parse rollup, exclude reviewer checks ---
unset -f expensive_gate_baseline_checks_status
HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
expensive_gate_unresolved_threads_status() { printf 'ok 0 %s\n' "$_1649_head"; }
# Pin harness mock + clear command hash; earlier areas may leave a different gh
# ahead on PATH or hashed from a temporary mock dir that was later removed.
export PATH="$MOCK_BIN:$PATH"
hash -r
# Deterministic reviewer-check names so exclusion cases do not depend on the
# live .ai-dev-workflow.yaml / local override contents in this checkout.
configured_reviewer_check_names_json() { printf '["Cursor Bugbot"]\n'; }

_1649_baseline_helper_row() {
  local rollup="$1"
  export MOCK_GH_PR_VIEW_ROLLUP="$rollup"
  export MOCK_GH_EXIT=0
  expensive_gate_baseline_checks_status 42 "$_1649_head"
}

_1649_green_rollup='{"statusCheckRollup":[{"name":"ShellCheck","status":"COMPLETED","conclusion":"SUCCESS"}],"headRefOid":"'"$_1649_head"'"}'
_1649_fail_rollup='{"statusCheckRollup":[{"name":"ShellCheck","status":"COMPLETED","conclusion":"FAILURE"},{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}],"headRefOid":"'"$_1649_head"'"}'
_1649_pending_rollup='{"statusCheckRollup":[{"name":"ShellCheck","status":"IN_PROGRESS","conclusion":null},{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}],"headRefOid":"'"$_1649_head"'"}'
_1649_exclude_rollup='{"statusCheckRollup":[{"name":"Cursor Bugbot","status":"IN_PROGRESS","conclusion":null},{"name":"ShellCheck","status":"COMPLETED","conclusion":"SUCCESS"}],"headRefOid":"'"$_1649_head"'"}'
_1649_empty_rollup='{"statusCheckRollup":[],"headRefOid":"'"$_1649_head"'"}'
_1649_reviewer_only_rollup='{"statusCheckRollup":[{"name":"Cursor Bugbot","status":"COMPLETED","conclusion":"SUCCESS"}],"headRefOid":"'"$_1649_head"'"}'

run_test "1649_s10_real_green" "green $_1649_head" \
  "$(_1649_baseline_helper_row "$_1649_green_rollup")"
run_test "1649_s10_real_failed" "failed $_1649_head" \
  "$(_1649_baseline_helper_row "$_1649_fail_rollup")"
run_test "1649_s10_real_pending" "pending $_1649_head" \
  "$(_1649_baseline_helper_row "$_1649_pending_rollup")"
# Pending reviewer-owned check + green non-reviewer → green (exclusion)
run_test "1649_s10_real_exclude_reviewer" "green $_1649_head" \
  "$(_1649_baseline_helper_row "$_1649_exclude_rollup")"
run_test "1649_s10_real_empty" "empty $_1649_head" \
  "$(_1649_baseline_helper_row "$_1649_empty_rollup")"
run_test "1649_s10_real_reviewer_only" "empty $_1649_head" \
  "$(_1649_baseline_helper_row "$_1649_reviewer_only_rollup")"
# Stale failed duplicate + newer green same name → green (pr-ci-loop normalization)
_1649_dup_rollup='{"statusCheckRollup":[{"name":"ShellCheck","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-01-01T00:00:00Z"},{"name":"ShellCheck","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-01-01T01:00:00Z"}],"headRefOid":"'"$_1649_head"'"}'
run_test "1649_s10_real_dup_latest_green" "green $_1649_head" \
  "$(_1649_baseline_helper_row "$_1649_dup_rollup")"
# #1879: the loop's own completion-guard StatusContext is not a baseline check.
# All real checks green + guard failing (left red by an earlier non-clean
# summary) -> green, so the gate cannot deadlock on its own output.
_1879_guard_fail_rollup='{"statusCheckRollup":[{"name":"ShellCheck","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"Reviewer-loop completion guard (#42)","state":"FAILURE"}],"headRefOid":"'"$_1649_head"'"}'
run_test "1879_guard_failure_excluded_green" "green $_1649_head" \
  "$(_1649_baseline_helper_row "$_1879_guard_fail_rollup")"
_1879_guard_pending_rollup='{"statusCheckRollup":[{"name":"ShellCheck","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"Reviewer-loop completion guard (#42)","state":"PENDING"}],"headRefOid":"'"$_1649_head"'"}'
run_test "1879_guard_pending_excluded_green" "green $_1649_head" \
  "$(_1649_baseline_helper_row "$_1879_guard_pending_rollup")"
# Planted violation: a failing real check alongside the failing guard is
# still reported failed — the exclusion removes only the guard.
_1879_planted_rollup='{"statusCheckRollup":[{"name":"ShellCheck","status":"COMPLETED","conclusion":"FAILURE"},{"__typename":"StatusContext","context":"Reviewer-loop completion guard (#42)","state":"FAILURE"}],"headRefOid":"'"$_1649_head"'"}'
run_test "1879_planted_real_failure_still_failed" "failed $_1649_head" \
  "$(_1649_baseline_helper_row "$_1879_planted_rollup")"
# A failing status whose name only resembles the guard is not excluded.
_1879_lookalike_rollup='{"statusCheckRollup":[{"name":"ShellCheck","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"Reviewer-loop completion guard","state":"FAILURE"}],"headRefOid":"'"$_1649_head"'"}'
run_test "1879_lookalike_status_still_failed" "failed $_1649_head" \
  "$(_1649_baseline_helper_row "$_1879_lookalike_rollup")"
# Only the guard on the rollup -> nothing to vouch for the head -> empty.
_1879_guard_only_rollup='{"statusCheckRollup":[{"__typename":"StatusContext","context":"Reviewer-loop completion guard (#42)","state":"SUCCESS"}],"headRefOid":"'"$_1649_head"'"}'
run_test "1879_guard_only_empty" "empty $_1649_head" \
  "$(_1649_baseline_helper_row "$_1879_guard_only_rollup")"
unset _1879_guard_fail_rollup _1879_guard_pending_rollup _1879_planted_rollup \
  _1879_lookalike_rollup _1879_guard_only_rollup
export MOCK_GH_EXIT=1
run_test "1649_s10_real_unavailable" "unavailable" \
  "$(expensive_gate_baseline_checks_status 42 "$_1649_head" | awk '{print $1}')"
export MOCK_GH_EXIT=0
unset MOCK_GH_PR_VIEW_ROLLUP
unset -f configured_reviewer_check_names_json
# Restore stubs for remaining gate scenarios.
expensive_gate_unresolved_threads_status() { printf 'ok 0 %s\n' "${MOCK_THREADS_HEAD:-$_1649_head}"; }
expensive_gate_baseline_checks_status() {
  printf '%s %s\n' "${MOCK_CHECKS_STATE:-green}" "${MOCK_CHECKS_HEAD:-$_1649_head}"
}
platforms=(local-ai-reviewer pr-agent codex-github)
platform_reviewed_heads=("local-ai-reviewer:$_1649_head")
platform_peer_evidence=("local-ai-reviewer|clean|" "pr-agent|clean|")

expensive_gate_unresolved_threads_status() { printf 'ok 0 %s\n' "$_1649_other"; }
expensive_gate_baseline_checks_status() { printf 'green %s\n' "$_1649_head"; }
_out="$(_1649_run_gate)"
run_test "1649_s11_threads_head_moved" "evidence_head_moved" "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"
expensive_gate_unresolved_threads_status() { printf 'ok 0 %s\n' "$_1649_head"; }
expensive_gate_baseline_checks_status() { printf 'green %s\n' "$_1649_other"; }
_out="$(_1649_run_gate)"
run_test "1649_s11_checks_head_moved" "evidence_head_moved" "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"

# --- Scenario 12: unreadable inputs ---
_out="$(_1649_run_gate 42 codex-github "")"
run_test "1649_s12_empty_head" "evidence_unavailable_head" "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"
expensive_gate_unresolved_threads_status() { printf 'unavailable - \n'; }
expensive_gate_baseline_checks_status() { printf 'green %s\n' "$_1649_head"; }
_out="$(_1649_run_gate)"
run_test "1649_s12_threads_fail" "evidence_unavailable_review_threads" \
  "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"
expensive_gate_unresolved_threads_status() { printf 'ok 0 %s\n' "$_1649_head"; }
expensive_gate_baseline_checks_status() { printf 'unavailable \n'; }
_out="$(_1649_run_gate)"
run_test "1649_s12_checks_fail" "evidence_unavailable_checks" \
  "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"

# Restore green stubs
_1649_stub_green_evidence
platforms=(local-ai-reviewer pr-agent codex-github)
platform_reviewed_heads=("local-ai-reviewer:$_1649_head")
platform_peer_evidence=("local-ai-reviewer|clean|" "pr-agent|clean|")

# --- Scenario 13 / 14: deferral cap + head-scoped ---
_1649_ledger_entries() {
  local n="$1" head="${2:-$_1649_head}"
  local i
  local _1649_json_entries="["
  for i in $(seq 1 "$n"); do
    [ "$i" -gt 1 ] && _1649_json_entries+=","
    _1649_json_entries+="{\"result\":\"needs_fixes\",\"reason\":\"expensive_gate_deferred\",\"head_sha\":\"$head\",\"expensive_gate\":{\"platform\":\"codex-github\",\"result\":\"deferred\",\"reason\":\"baseline_checks_pending\",\"head\":\"$head\"}}"
  done
  _1649_json_entries+="]"
  printf '%s\n' "<!-- reviewer-loop-history:v1 -->
\`\`\`json
{\"schema\":\"reviewer_loop_history.v1\",\"history_status\":\"available\",\"entries\":${_1649_json_entries}}
\`\`\`"
}

expensive_gate_max_deferrals=3
# Force a defer reason (stale local) with 3 prior deferrals → cap
platform_reviewed_heads=("local-ai-reviewer:$_1649_other")
EXPENSIVE_GATE_MOCK_LEDGER_BODY="$(_1649_ledger_entries 3)"
_out="$(_1649_run_gate)"
run_test "1649_s13_cap" "deferral_cap" "$(_1649_kv EXPENSIVE_GATE_RESULT "$_out")"
run_test "1649_s13_escalation" "expensive_gate_deferral_cap" \
  "$(_1649_kv EXPENSIVE_GATE_ESCALATION "$_out")"
run_test "1649_s13_reason_preserved" "local_evidence_stale" \
  "$(_1649_kv EXPENSIVE_GATE_REASON "$_out")"

EXPENSIVE_GATE_MOCK_LEDGER_BODY="$(_1649_ledger_entries 2)"
_out="$(_1649_run_gate)"
run_test "1649_s13_under_cap_defers" "deferred" "$(_1649_kv EXPENSIVE_GATE_RESULT "$_out")"

# Scenario 14: deferrals on other head do not count
EXPENSIVE_GATE_MOCK_LEDGER_BODY="$(_1649_ledger_entries 3 "$_1649_other")"
_out="$(_1649_run_gate)"
run_test "1649_s14_other_head_ignored" "deferred" "$(_1649_kv EXPENSIVE_GATE_RESULT "$_out")"
run_test "1649_s14_deferrals_zero" "0" "$(_1649_kv EXPENSIVE_GATE_DEFERRALS "$_out")"

# --- Scenario 18: legacy ledger without expensive_gate still parses ---
_legacy_body='<!-- reviewer-loop-history:v1 -->
```json
{"schema":"reviewer_loop_history.v1","history_status":"available","entries":[{"iteration":1,"result":"clean","reason":"","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","platforms":[]}]}
```'
_legacy_payload="$(reviewer_loop_history_payload_from_existing "$_legacy_body" needs_fixes expensive_gate_deferred "codex-github" 0 0 0 "" 0 0 "")"
run_test "1649_s18_legacy_parses" "available" \
  "$(printf '%s\n' "$_legacy_payload" | jq -r '.history_status')"
run_test "1649_s18_has_entries" "2" \
  "$(printf '%s\n' "$_legacy_payload" | jq -r '.entries | length')"

# --- Scenario 19: unreadable budget ---
EXPENSIVE_GATE_MOCK_LEDGER_BODY="<!-- reviewer-loop-history:v1 -->
\`\`\`json
{not-json
\`\`\`"
platform_reviewed_heads=("local-ai-reviewer:$_1649_other")
_out="$(_1649_run_gate)"
run_test "1649_s19_unreadable" "deferral_cap" "$(_1649_kv EXPENSIVE_GATE_RESULT "$_out")"
run_test "1649_s19_escalation" "expensive_gate_deferral_budget_unreadable" \
  "$(_1649_kv EXPENSIVE_GATE_ESCALATION "$_out")"
run_test "1649_s19_deferrals_neg1" "-1" "$(_1649_kv EXPENSIVE_GATE_DEFERRALS "$_out")"

# --- Scenario 19b: absent ledger → 0 ---
unset EXPENSIVE_GATE_MOCK_LEDGER_BODY
EXPENSIVE_GATE_MOCK_LEDGER_BODY=""
_out="$(_1649_run_gate)"
run_test "1649_s19b_absent_zero" "0" "$(_1649_kv EXPENSIVE_GATE_DEFERRALS "$_out")"
run_test "1649_s19b_defers_normally" "deferred" "$(_1649_kv EXPENSIVE_GATE_RESULT "$_out")"

# Build entry includes expensive_gate object
expensive_gate_last_platform="codex-github"
expensive_gate_last_result="deferred"
expensive_gate_last_reason="local_evidence_stale"
expensive_gate_last_head="$_1649_head"
loop_head_sha="$_1649_head"
pr_number=""
current_run_id="test-run"
platform_reviewed_heads=("local-ai-reviewer:$_1649_head")
_entry="$(reviewer_loop_history_build_entry 1 needs_fixes expensive_gate_deferred "local-ai-reviewer,codex-github" 0 0 0 "" 0 0 "")"
run_test "1649_history_has_gate" "deferred" \
  "$(printf '%s\n' "$_entry" | jq -r '.expensive_gate.result')"
run_test "1649_history_gate_reason" "local_evidence_stale" \
  "$(printf '%s\n' "$_entry" | jq -r '.expensive_gate.reason')"

# Cleanup stubs / state
unset EXPENSIVE_GATE_MOCK_LEDGER_BODY
unset -f expensive_gate_unresolved_threads_status expensive_gate_baseline_checks_status 2>/dev/null || true
# Re-source would be heavy; leave defaults — later suites redefine if needed.
expensive_gate_last_platform=""
expensive_gate_last_result=""
expensive_gate_last_reason=""
expensive_gate_last_head=""
platform_peer_evidence=()
platform_reviewed_heads=()
platforms=()
phase_after_clean_platforms=()
unset _1649_head _1649_other _out _entry _legacy_body _legacy_payload _warn _val
unset _orig_cfg _orig_hc

echo "=== Area 1649 complete ==="

# ---------------------------------------------------------------------------
# Area 1650: strict_spec ledger object (#1650 scenario 12)
# ---------------------------------------------------------------------------
echo "=== Area 1650: strict_spec ledger object ==="

pr_number=""
current_run_id="1650-ledger"
unresolved_thread_count=0
late_thread_count=0
expensive_gate_last_result=""

# Applied: state + count + checks present; reason absent
strict_spec_recorded=1
strict_spec_state="applied"
strict_spec_count="3"
strict_spec_checks="ac_consistency,gate_matrix"
strict_spec_applied="ac_consistency,gate_matrix"
strict_spec_unknown_count=""
strict_spec_reason=""
_entry="$(reviewer_loop_history_build_entry 1 clean "" "local-ai-reviewer" 0 0 0 "" 0 0 "")"
run_test "1650_ledger_applied_state" "applied" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_spec.state')"
run_test "1650_ledger_applied_count" "3" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_spec.count')"
run_test "1650_ledger_applied_has_checks" "true" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_spec | has("checks")')"
run_test "1650_ledger_applied_has_applied" "true" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_spec | has("applied")')"
run_test "1650_ledger_applied_no_reason" "false" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_spec | has("reason")')"

# not_applicable: only state; count/checks/reason absent
strict_spec_state="not_applicable"
strict_spec_count=""
strict_spec_checks=""
strict_spec_applied=""
strict_spec_unknown_count=""
strict_spec_reason=""
_entry="$(reviewer_loop_history_build_entry 1 clean "" "local-ai-reviewer" 0 0 0 "" 0 0 "")"
run_test "1650_ledger_na_state" "not_applicable" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_spec.state')"
run_test "1650_ledger_na_no_count" "false" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_spec | has("count")')"
run_test "1650_ledger_na_no_checks" "false" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_spec | has("checks")')"
run_test "1650_ledger_na_no_reason" "false" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_spec | has("reason")')"

# No local reviewer: object itself absent
strict_spec_recorded=0
strict_spec_state=""
_entry="$(reviewer_loop_history_build_entry 1 clean "" "bugbot" 0 0 0 "" 0 0 "")"
run_test "1650_ledger_absent_object" "false" \
  "$(printf '%s\n' "$_entry" | jq -r 'has("strict_spec")')"

# unavailable carries reason only
strict_spec_recorded=1
strict_spec_state="unavailable"
strict_spec_reason="checklist_unreadable"
strict_spec_count=""
strict_spec_checks=""
strict_spec_applied=""
_entry="$(reviewer_loop_history_build_entry 1 clean "" "local-ai-reviewer" 0 0 0 "" 0 0 "")"
run_test "1650_ledger_unavail_reason" "checklist_unreadable" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_spec.reason')"
run_test "1650_ledger_unavail_no_count" "false" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_spec | has("count")')"

unset strict_spec_recorded strict_spec_state strict_spec_count strict_spec_checks strict_spec_applied
unset strict_spec_unknown_count strict_spec_reason _entry current_run_id
unset unresolved_thread_count late_thread_count pr_number

echo "=== Area 1650 complete ==="

# ---------------------------------------------------------------------------
# Area 1655: strict_plan ledger object (#1655 scenario 16)
# ---------------------------------------------------------------------------
echo "=== Area 1655: strict_plan ledger object ==="

pr_number=""
current_run_id="1655-ledger"
unresolved_thread_count=0
late_thread_count=0
expensive_gate_last_result=""

strict_plan_recorded=1
strict_plan_state="applied"
strict_plan_count="2"
strict_plan_checks="phase_ordering,dependency_state"
strict_plan_applied="source_declaration,phase_ordering,dependency_state,reversal_risk"
strict_plan_unknown_count=""
strict_plan_reason=""
_entry="$(reviewer_loop_history_build_entry 1 clean "" "local-ai-reviewer" 0 0 0 "" 0 0 "")"
run_test "1655_ledger_applied_state" "applied" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_plan.state')"
run_test "1655_ledger_applied_count" "2" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_plan.count')"
run_test "1655_ledger_applied_checks" "true" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_plan | has("checks")')"
run_test "1655_ledger_applied_applied" "true" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_plan | has("applied")')"
run_test "1655_ledger_applied_no_reason" "false" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_plan | has("reason")')"

strict_plan_state="not_applicable"
strict_plan_count=""
strict_plan_checks=""
strict_plan_applied=""
strict_plan_unknown_count=""
strict_plan_reason="stage_not_plan"
_entry="$(reviewer_loop_history_build_entry 1 clean "" "local-ai-reviewer" 0 0 0 "" 0 0 "")"
run_test "1655_ledger_na_state" "not_applicable" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_plan.state')"
run_test "1655_ledger_na_reason" "stage_not_plan" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_plan.reason')"
run_test "1655_ledger_na_no_count" "false" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_plan | has("count")')"
run_test "1655_ledger_na_no_applied" "false" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_plan | has("applied")')"

strict_plan_recorded=0
strict_plan_state=""
_entry="$(reviewer_loop_history_build_entry 1 clean "" "bugbot" 0 0 0 "" 0 0 "")"
run_test "1655_ledger_absent_object" "false" \
  "$(printf '%s\n' "$_entry" | jq -r 'has("strict_plan")')"

strict_plan_recorded=1
strict_plan_state="unavailable"
strict_plan_reason="checklist_unreadable"
strict_plan_count=""
strict_plan_checks=""
strict_plan_applied=""
_entry="$(reviewer_loop_history_build_entry 1 clean "" "local-ai-reviewer" 0 0 0 "" 0 0 "")"
run_test "1655_ledger_unavail_reason" "checklist_unreadable" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_plan.reason')"
run_test "1655_ledger_unavail_no_count" "false" \
  "$(printf '%s\n' "$_entry" | jq -r '.strict_plan | has("count")')"

unset strict_plan_recorded strict_plan_state strict_plan_count strict_plan_checks
unset strict_plan_applied strict_plan_unknown_count strict_plan_reason _entry
unset current_run_id unresolved_thread_count late_thread_count pr_number

echo "=== Area 1655 complete ==="

# ---------------------------------------------------------------------------
# Area 1651: missed-finding telemetry
# Scenarios 1–3, 6–16 (ancestry 4/5 live in test-reviewer-loop-commit-ancestry.sh)
# ---------------------------------------------------------------------------
echo "=== Area 1651: missed-finding telemetry ==="

HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

# Fixed 40-hex SHAs — harness git is mocked and rejects real rev-parse.
# Ancestry relationships are stubbed below for evidence-state cases; real
# ancestry coverage lives in test-reviewer-loop-commit-ancestry.sh.
_1651_descendant='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
_1651_ancestor='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
_1651_unrelated='cccccccccccccccccccccccccccccccccccccccc'

# Stub ancestry so evidence-state tests do not depend on real git objects.
_1651_real_ancestry="$(declare -f reviewer_loop_commit_ancestry)"
reviewer_loop_commit_ancestry() {
  local clean="${1:-}" reviewed="${2:-}"
  [ -n "$clean" ] && [ -n "$reviewed" ] || { printf 'undecidable\n'; return 0; }
  if [ "$clean" = "$reviewed" ]; then printf 'same\n'; return 0; fi
  if [ "$clean" = "$_1651_ancestor" ] && [ "$reviewed" = "$_1651_descendant" ]; then
    printf 'ancestor\n'; return 0
  fi
  if [ "$clean" = "$_1651_descendant" ] && [ "$reviewed" = "$_1651_ancestor" ]; then
    printf 'descendant\n'; return 0
  fi
  if [ "$clean" = "$_1651_unrelated" ] || [ "$reviewed" = "$_1651_unrelated" ]; then
    printf 'unrelated\n'; return 0
  fi
  printf 'undecidable\n'
}

_1651_cfg=$'local-ai-reviewer\ncodex-github\nbugbot\n'

# --- Scenario 1 / AC-4a: most recent verdict, not most recent clean ---
_1651_hist="$(jq -nc --arg a "$_1651_ancestor" --arg d "$_1651_descendant" '
  {schema:"reviewer_loop_history.v1", entries:[
    {iteration:2, platform_results:[{platform:"local-ai-reviewer",result:"clean",raw_result:"clean",raw_reason:""}],
     reviewed_heads:[{platform:"local-ai-reviewer",reviewed_head:$a,state:"current",reason:""}]},
    {iteration:5, platform_results:[{platform:"local-ai-reviewer",result:"needs_fixes",raw_result:"needs_fixes",raw_reason:""}],
     reviewed_heads:[{platform:"local-ai-reviewer",reviewed_head:$d,state:"current",reason:""}]}
  ]}')"
_1651_v="$(reviewer_loop_local_latest_verdict "$_1651_hist" "$_1651_cfg")"
run_test "1651_s1_recency_over_clean" "needs_fixes" \
  "$(printf '%s\n' "$_1651_v" | jq -r '.outcome')"
run_test "1651_s1_iteration_5" "5" \
  "$(printf '%s\n' "$_1651_v" | jq -r '.iteration')"

# --- Scenario 1a: current round wins (synthetic composition) ---
platform_result_records=(
  "$(reviewer_loop_platform_result_record_json local-ai-reviewer clean "")"
  "$(reviewer_loop_platform_result_record_json codex-github needs_fixes "")"
)
platform_reviewed_heads=(
  "local-ai-reviewer:${_1651_descendant}"
  "codex-github:${_1651_descendant}"
)
platform_blocking_outputs=(
  $'codex-github\036RESULT=needs_fixes\nBLOCKING_COUNT=2\nBLOCKING_1_PATH=a.ts\nBLOCKING_2_PATH=b.ts\n'
)
loop_head_sha="$_1651_descendant"
# Prior history says needs_fixes; current round local is clean — AC-1 same-round case
_1651_prior="$(jq -nc --arg h "$_1651_ancestor" '
  {schema:"reviewer_loop_history.v1", entries:[
    {iteration:1, platform_results:[{platform:"local-ai-reviewer",result:"needs_fixes",raw_result:"needs_fixes",raw_reason:""}],
     reviewed_heads:[{platform:"local-ai-reviewer",reviewed_head:$h,state:"current",reason:""}]}
  ]}')"
missed_finding_attribution_reports=""
_1651_recs="$(reviewer_loop_missed_finding_records "$_1651_prior" "$_1651_cfg" 2)"
run_test "1651_s1a_confirmed_miss" "confirmed_miss" \
  "$(printf '%s\n' "$_1651_recs" | jq -r '.[0].classification')"
run_test "1651_s1a_same_commit_state" "clean_same_commit" \
  "$(printf '%s\n' "$_1651_recs" | jq -r '.[0].local_evidence_state')"

# --- Scenario 1b: no prior entry — current round still used ---
_1651_recs="$(reviewer_loop_missed_finding_records '{"schema":"reviewer_loop_history.v1","entries":[]}' "$_1651_cfg" 1)"
run_test "1651_s1b_no_prior_confirmed" "confirmed_miss" \
  "$(printf '%s\n' "$_1651_recs" | jq -r '.[0].classification')"

# --- Scenario 2 / 2b: not_yet_run vs not_configured; whole-line membership ---
_1651_empty='{"schema":"reviewer_loop_history.v1","entries":[]}'
run_test "1651_s2_not_yet_run" "not_yet_run" \
  "$(reviewer_loop_local_latest_verdict "$_1651_empty" "$_1651_cfg" | jq -r '.outcome')"
run_test "1651_s2_not_configured" "not_configured" \
  "$(reviewer_loop_local_latest_verdict "$_1651_empty" $'bugbot\ncodex-github\n' | jq -r '.outcome')"
run_test "1651_s2b_substring_rejected" "not_configured" \
  "$(reviewer_loop_local_latest_verdict "$_1651_empty" $'local-ai-reviewer-v2\n' | jq -r '.outcome')"
run_test "1651_s2b_sole_entry" "not_yet_run" \
  "$(reviewer_loop_local_latest_verdict "$_1651_empty" $'local-ai-reviewer\n' | jq -r '.outcome')"

# --- Scenario 2c: long configured list with early match (here-string, not pipe) ---
_1651_long="$(printf 'local-ai-reviewer\n'; for _i in $(seq 1 499); do printf 'other-%s\n' "$_i"; done)"
run_test "1651_s2c_long_list" "not_yet_run" \
  "$(reviewer_loop_local_latest_verdict "$_1651_empty" "$_1651_long" | jq -r '.outcome')"

# --- Scenario 2d: filtered invocation must not hide prior local verdict ---
_1651_hist="$(jq -nc --arg h "$_1651_descendant" '
  {schema:"reviewer_loop_history.v1", entries:[
    {iteration:1, platform_results:[{platform:"local-ai-reviewer",result:"clean",raw_result:"clean",raw_reason:""}],
     reviewed_heads:[{platform:"local-ai-reviewer",reviewed_head:$h,state:"current",reason:""}]}
  ]}')"
run_test "1651_s2d_filtered_invocation_uses_history" "clean" \
  "$(reviewer_loop_local_latest_verdict "$_1651_hist" $'bugbot\ncodex-github\n' | jq -r '.outcome')"

# --- Scenario 2a: skipped/not_configured while list contains reviewer → unavailable ---
_1651_hist="$(jq -nc --arg h "$_1651_descendant" '
  {schema:"reviewer_loop_history.v1", entries:[
    {iteration:1, platform_results:[{platform:"local-ai-reviewer",result:"not_configured",raw_result:"skipped",raw_reason:"not_configured"}],
     reviewed_heads:[{platform:"local-ai-reviewer",reviewed_head:$h,state:"current",reason:""}]}
  ]}')"
run_test "1651_s2a_list_wins" "unavailable" \
  "$(reviewer_loop_local_latest_verdict "$_1651_hist" "$_1651_cfg" | jq -r '.outcome')"

# --- Scenario 3 / 3a: entries exist but no platform_results → unknown ---
_1651_hist="$(jq -nc '{schema:"reviewer_loop_history.v1", entries:[{iteration:1, platforms:["local-ai-reviewer"], result:"clean"}]}')"
run_test "1651_s3_no_platform_results" "unknown" \
  "$(reviewer_loop_local_latest_verdict "$_1651_hist" "$_1651_cfg" | jq -r '.outcome')"
run_test "1651_s3a_ignore_aggregate_clean" "unknown" \
  "$(reviewer_loop_local_latest_verdict "$_1651_hist" "$_1651_cfg" | jq -r '.outcome')"

# --- Scenario 3b: local platform_results, not aggregate ---
_1651_hist="$(jq -nc --arg h "$_1651_descendant" '
  {schema:"reviewer_loop_history.v1", entries:[
    {iteration:1, result:"needs_fixes",
     platform_results:[
       {platform:"local-ai-reviewer",result:"clean",raw_result:"clean",raw_reason:""},
       {platform:"codex-github",result:"needs_fixes",raw_result:"needs_fixes",raw_reason:""}
     ],
     reviewed_heads:[{platform:"local-ai-reviewer",reviewed_head:$h,state:"current",reason:""}]}
  ]}')"
run_test "1651_s3b_local_not_aggregate" "clean" \
  "$(reviewer_loop_local_latest_verdict "$_1651_hist" "$_1651_cfg" | jq -r '.outcome')"

# --- Scenario 6: evidence-state mapping (normalized outcomes) ---
_1651_verdict() { jq -nc --arg o "$1" --arg h "$2" '{outcome:$o, head_sha:$h, iteration:1}'; }
run_test "1651_s6_same" "clean_same_commit" \
  "$(reviewer_loop_local_evidence_state "$(_1651_verdict clean "$_1651_descendant")" "$_1651_descendant")"
run_test "1651_s6_earlier" "clean_earlier_commit" \
  "$(reviewer_loop_local_evidence_state "$(_1651_verdict clean "$_1651_ancestor")" "$_1651_descendant")"
run_test "1651_s6_later" "clean_later_commit" \
  "$(reviewer_loop_local_evidence_state "$(_1651_verdict clean "$_1651_descendant")" "$_1651_ancestor")"
run_test "1651_s6_unrelated" "clean_unrelated_commit" \
  "$(reviewer_loop_local_evidence_state "$(_1651_verdict clean "$_1651_unrelated")" "$_1651_descendant")"
run_test "1651_s6_not_clean" "not_clean" \
  "$(reviewer_loop_local_evidence_state "$(_1651_verdict needs_fixes "$_1651_descendant")" "$_1651_descendant")"
run_test "1651_s6_skipped" "skipped" \
  "$(reviewer_loop_local_evidence_state "$(_1651_verdict skipped "")" "$_1651_descendant")"
run_test "1651_s6_unavailable" "unavailable" \
  "$(reviewer_loop_local_evidence_state "$(_1651_verdict unavailable "")" "$_1651_descendant")"
run_test "1651_s6_not_yet_run" "not_yet_run" \
  "$(reviewer_loop_local_evidence_state "$(_1651_verdict not_yet_run "")" "$_1651_descendant")"
run_test "1651_s6_not_configured" "not_configured" \
  "$(reviewer_loop_local_evidence_state "$(_1651_verdict not_configured "")" "$_1651_descendant")"
run_test "1651_s6_unknown_outcome" "unknown" \
  "$(reviewer_loop_local_evidence_state "$(_1651_verdict weird "")" "$_1651_descendant")"
run_test "1651_s6a_empty_local_head" "unknown" \
  "$(reviewer_loop_local_evidence_state "$(_1651_verdict clean "")" "$_1651_descendant")"

# --- Scenario 6b: normalization table ---
run_test "1651_s6b_clean" "clean" "$(reviewer_loop_normalize_platform_outcome clean "")"
run_test "1651_s6b_needs_fixes" "needs_fixes" "$(reviewer_loop_normalize_platform_outcome needs_fixes "")"
run_test "1651_s6b_skipped_unavail" "unavailable" "$(reviewer_loop_normalize_platform_outcome skipped unavailable)"
run_test "1651_s6b_skipped_not_cfg" "not_configured" "$(reviewer_loop_normalize_platform_outcome skipped not_configured)"
run_test "1651_s6b_skipped_other" "skipped" "$(reviewer_loop_normalize_platform_outcome skipped deliberate)"
run_test "1651_s6b_escalate" "unavailable" "$(reviewer_loop_normalize_platform_outcome escalate timeout)"
run_test "1651_s6b_unknown" "unknown" "$(reviewer_loop_normalize_platform_outcome weird "")"
_1651_rec="$(reviewer_loop_platform_result_record_json codex-github skipped unavailable)"
run_test "1651_s6b_raw_retained" "skipped" "$(printf '%s\n' "$_1651_rec" | jq -r '.raw_result')"
run_test "1651_s6b_raw_reason" "unavailable" "$(printf '%s\n' "$_1651_rec" | jq -r '.raw_reason')"
run_test "1651_s6b_no_head_field" "false" "$(printf '%s\n' "$_1651_rec" | jq -r 'has("reviewed_head") or has("head")')"

# --- Scenario 7: local reviewer findings produce no record ---
platform_result_records=("$(reviewer_loop_platform_result_record_json local-ai-reviewer needs_fixes "")")
platform_reviewed_heads=("local-ai-reviewer:${_1651_descendant}")
platform_blocking_outputs=($'local-ai-reviewer\036RESULT=needs_fixes\nBLOCKING_COUNT=1\nBLOCKING_1_PATH=x.ts\n')
_1651_recs="$(reviewer_loop_missed_finding_records '{"schema":"reviewer_loop_history.v1","entries":[]}' "$_1651_cfg" 1)"
run_test "1651_s7_local_excluded" "0" "$(printf '%s\n' "$_1651_recs" | jq 'length')"

# --- Scenario 8: advisory-only (non needs_fixes) produces no record ---
platform_result_records=("$(reviewer_loop_platform_result_record_json codex-github clean "")")
platform_reviewed_heads=("codex-github:${_1651_descendant}")
platform_blocking_outputs=()
_1651_recs="$(reviewer_loop_missed_finding_records '{"schema":"reviewer_loop_history.v1","entries":[]}' "$_1651_cfg" 1)"
run_test "1651_s8_advisory_excluded" "0" "$(printf '%s\n' "$_1651_recs" | jq 'length')"

# --- Scenario 9: not_clean still produces a denominator record ---
platform_result_records=(
  "$(reviewer_loop_platform_result_record_json local-ai-reviewer needs_fixes "")"
  "$(reviewer_loop_platform_result_record_json codex-github needs_fixes "")"
)
platform_reviewed_heads=(
  "local-ai-reviewer:${_1651_descendant}"
  "codex-github:${_1651_descendant}"
)
platform_blocking_outputs=($'codex-github\036RESULT=needs_fixes\nBLOCKING_COUNT=1\nBLOCKING_1_PATH=a.ts\n')
_1651_recs="$(reviewer_loop_missed_finding_records '{"schema":"reviewer_loop_history.v1","entries":[]}' "$_1651_cfg" 1)"
run_test "1651_s9_denominator_not_clean" "not_a_miss" \
  "$(printf '%s\n' "$_1651_recs" | jq -r '.[0].classification')"
run_test "1651_s9_state_not_clean" "not_clean" \
  "$(printf '%s\n' "$_1651_recs" | jq -r '.[0].local_evidence_state')"

# --- Scenario 10: two rounds accumulate (builder called twice independently) ---
platform_result_records=(
  "$(reviewer_loop_platform_result_record_json local-ai-reviewer clean "")"
  "$(reviewer_loop_platform_result_record_json codex-github needs_fixes "")"
)
platform_reviewed_heads=("local-ai-reviewer:${_1651_descendant}" "codex-github:${_1651_descendant}")
platform_blocking_outputs=($'codex-github\036RESULT=needs_fixes\nBLOCKING_COUNT=1\nBLOCKING_1_PATH=a.ts\n')
_1651_r1="$(reviewer_loop_missed_finding_records '{"schema":"reviewer_loop_history.v1","entries":[]}' "$_1651_cfg" 1)"
_1651_r2="$(reviewer_loop_missed_finding_records '{"schema":"reviewer_loop_history.v1","entries":[]}' "$_1651_cfg" 2)"
run_test "1651_s10_two_records" "2" \
  "$(jq -nc --argjson a "$_1651_r1" --argjson b "$_1651_r2" '$a + $b | length')"

# --- Scenario 13a / 13a-i: path dedupe + full path list in record ---
platform_result_records=(
  "$(reviewer_loop_platform_result_record_json local-ai-reviewer clean "")"
  "$(reviewer_loop_platform_result_record_json codex-github needs_fixes "")"
)
platform_reviewed_heads=("local-ai-reviewer:${_1651_descendant}" "codex-github:${_1651_descendant}")
_1651_out=$'codex-github\036RESULT=needs_fixes\nBLOCKING_COUNT=8\n'
for _i in 1 2 3 4 5 6 7 8; do
  case "$_i" in
    1|2|3) _p=a.ts ;;
    4|5) _p=b.ts ;;
    *) _p=c.ts ;;
  esac
  _1651_out="${_1651_out}BLOCKING_${_i}_PATH=${_p}"$'\n'
done
platform_blocking_outputs=("$_1651_out")
_1651_recs="$(reviewer_loop_missed_finding_records '{"schema":"reviewer_loop_history.v1","entries":[]}' "$_1651_cfg" 1)"
run_test "1651_s13a_path_total_deduped" "3" \
  "$(printf '%s\n' "$_1651_recs" | jq -r '.[0].path_total')"
run_test "1651_s13a_distinct_paths" "3" \
  "$(printf '%s\n' "$_1651_recs" | jq -r '.[0].paths | unique | length')"

# twelve-file record for 13a-i
_1651_paths="$(jq -nc '[range(1;13) | "file-\(.).ts"]')"
_1651_rec="$(jq -nc --arg h "$_1651_descendant" --argjson paths "$_1651_paths" '
  {reviewer:"codex-github", reviewed_head:$h, blocking_count:12, paths:$paths, path_total:12,
   local_evidence_state:"clean_same_commit", classification:"confirmed_miss"}')"
run_test "1651_s13ai_record_holds_all" "12" \
  "$(printf '%s\n' "$_1651_rec" | jq -r '.paths | length')"
_1651_line="$(reviewer_loop_missed_finding_summary_line "$_1651_rec")"
run_test "1651_s13_line_le_200" "1" "$([ "${#_1651_line}" -le 200 ] && echo 1 || echo 0)"
run_contains "1651_s13c_iii_enum" "[confirmed_miss]" "$_1651_line"
run_contains "1651_s13c_iii_label" "Clean, same commit" "$_1651_line"
run_contains "1651_s13c_remainder" "+9 more" "$_1651_line"

# zero-path long paths (budget derived)
_1651_longpath="$(printf 'p%.0s' {1..90})"
_1651_rec="$(jq -nc --arg h "$_1651_descendant" --arg p "$_1651_longpath" '
  {reviewer:"codex-github", reviewed_head:$h, blocking_count:7, paths:[$p,$p,$p], path_total:12,
   local_evidence_state:"clean_same_commit", classification:"confirmed_miss"}')"
_1651_line="$(reviewer_loop_missed_finding_summary_line "$_1651_rec")"
run_test "1651_s13_zero_path_le_200" "1" "$([ "${#_1651_line}" -le 200 ] && echo 1 || echo 0)"
run_contains "1651_s13_zero_path_remainder" "+12 more" "$_1651_line"

# --- Scenario 13c-ii: worst realistic line ---
_1651_rec="$(jq -nc --arg h "$_1651_descendant" '
  {reviewer:"claude-code-action", reviewed_head:$h, blocking_count:9999999, path_total:9999999,
   paths:["short.ts","mid.ts","ok.ts"], local_evidence_state:"clean_earlier_commit",
   classification:"possible_miss"}')"
_1651_line="$(reviewer_loop_missed_finding_summary_line "$_1651_rec")"
run_test "1651_s13cii_le_200" "1" "$([ "${#_1651_line}" -le 200 ] && echo 1 || echo 0)"
run_contains "1651_s13cii_exact_counts" "9999999 blocking, 9999999 files" "$_1651_line"
run_contains "1651_s13cii_possible" "[possible_miss]" "$_1651_line"

# --- Scenario 13d: no REVIEWED_HEAD → no record even with loop_head_sha ---
platform_result_records=(
  "$(reviewer_loop_platform_result_record_json local-ai-reviewer clean "")"
  "$(reviewer_loop_platform_result_record_json codex-github needs_fixes "")"
)
platform_reviewed_heads=("local-ai-reviewer:${_1651_descendant}" "codex-github:")
platform_blocking_outputs=($'codex-github\036RESULT=needs_fixes\nBLOCKING_COUNT=1\nBLOCKING_1_PATH=a.ts\n')
loop_head_sha="$_1651_descendant"
missed_finding_attribution_reports=""
missed_findings_json='[]'
reviewer_loop_missed_finding_records '{"schema":"reviewer_loop_history.v1","entries":[]}' "$_1651_cfg" 1 >/dev/null
_1651_recs="$missed_findings_json"
run_test "1651_s13d_no_record" "0" "$(printf '%s\n' "$_1651_recs" | jq 'length')"
run_contains "1651_s13d_attribution_report" "could not be established" "$missed_finding_attribution_reports"

# --- Scenario 13e: single commit_id emits head; two distinct commits do not ---
_1651_head_out="$(printf '%s\n' "{\"commit_id\":\"$_1651_descendant\"}" \
  | reviewer_loop_print_reviewed_head_from_json_lines | grep '^REVIEWED_HEAD=' | cut -d= -f2- || true)"
run_test "1651_s13e_single_commit" "$_1651_descendant" "$_1651_head_out"
_1651_head_count="$(printf '%s\n' \
  "{\"commit_id\":\"$_1651_descendant\"}" \
  "{\"commit_id\":\"$_1651_ancestor\"}" \
  | reviewer_loop_print_reviewed_head_from_json_lines | grep -c '^REVIEWED_HEAD=' || true)"
run_test "1651_s13e_two_commits_no_head" "0" "$_1651_head_count"

# --- Scenario 13f: issue-comment-only / no-head adapters produce no record ---
for _1651_plat in claude-code-action pr-agent; do
  platform_result_records=(
    "$(reviewer_loop_platform_result_record_json local-ai-reviewer clean "")"
    "$(reviewer_loop_platform_result_record_json "$_1651_plat" needs_fixes "")"
  )
  platform_reviewed_heads=("local-ai-reviewer:${_1651_descendant}" "${_1651_plat}:")
  platform_blocking_outputs=("${_1651_plat}"$'\036'"RESULT=needs_fixes"$'\n'"BLOCKING_COUNT=1"$'\n'"BLOCKING_1_PATH=a.ts"$'\n')
  loop_head_sha="$_1651_descendant"
  missed_finding_attribution_reports=""
  missed_findings_json='[]'
  reviewer_loop_missed_finding_records '{"schema":"reviewer_loop_history.v1","entries":[]}' "$_1651_cfg" 1 >/dev/null
  run_test "1651_s13f_${_1651_plat}_no_record" "0" \
    "$(printf '%s\n' "$missed_findings_json" | jq 'length')"
  run_contains "1651_s13f_${_1651_plat}_report" "could not be established" "$missed_finding_attribution_reports"
done
unset _1651_plat _1651_head_out _1651_head_count

# --- Scenario 14: history entry fields ---
pr_number=""
current_run_id="1651-ledger"
unresolved_thread_count=0
late_thread_count=0
expensive_gate_last_result=""
strict_spec_recorded=0
platform_reviewed_heads=("local-ai-reviewer:${_1651_descendant}")
platform_results_json="$(jq -nc '[{platform:"local-ai-reviewer",result:"clean",raw_result:"clean",raw_reason:""}]')"
missed_findings_json='[]'
loop_head_sha="$_1651_descendant"
_entry="$(reviewer_loop_history_build_entry 1 clean "" "local-ai-reviewer" 0 0 0 "" 0 0 "")"
for _field in iteration recorded_at head_sha classification_head reviewed_heads run_id result reason platforms \
  blocking_count suggestion_count unresolved_thread_count late_threads_found phase_after_clean \
  small_findings_only small_findings_stop small_findings_rounds small_findings_required_rounds \
  small_findings_paths platform_results missed_findings; do
  run_test "1651_s14_has_${_field}" "true" \
    "$(printf '%s\n' "$_entry" | jq -r --arg f "$_field" 'has($f)')"
done
run_test "1651_s14a_no_head_in_platform_results" "false" \
  "$(printf '%s\n' "$_entry" | jq -r '.platform_results[0] | has("reviewed_head") or has("head")')"

# --- Scenario 15: twenty records ≤ 4000 chars / 20 lines ---
_1651_lines=""
_1651_total=0
for _i in $(seq 1 20); do
  _1651_rec="$(jq -nc --arg h "$_1651_descendant" --arg r "codex-github" '
    {reviewer:$r, reviewed_head:$h, blocking_count:99, path_total:12,
     paths:["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.ts",
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.ts",
            "cccccccccccccccccccccccccccccccccccccccccccccccccc.ts"],
     local_evidence_state:"clean_same_commit", classification:"confirmed_miss"}')"
  _1651_line="$(reviewer_loop_missed_finding_summary_line "$_1651_rec")"
  _1651_lines="${_1651_lines}${_1651_line}"$'\n'
  _1651_total=$((_1651_total + ${#_1651_line}))
done
run_test "1651_s15_line_count" "20" "$(printf '%s' "$_1651_lines" | grep -c .)"
run_test "1651_s15_char_budget" "1" "$([ "$_1651_total" -le 4000 ] && echo 1 || echo 0)"

# --- Scenario 16 / 16a: classification enum ---
run_test "1651_s16a_confirmed" "confirmed_miss" "$(reviewer_loop_missed_finding_classification clean_same_commit)"
run_test "1651_s16a_possible" "possible_miss" "$(reviewer_loop_missed_finding_classification clean_earlier_commit)"
for _st in clean_later_commit clean_unrelated_commit not_clean skipped unavailable not_yet_run not_configured unknown; do
  run_test "1651_s16a_${_st}" "not_a_miss" "$(reviewer_loop_missed_finding_classification "$_st")"
done

# --- Scenario 16b: two platforms, different heads ---
platform_result_records=(
  "$(reviewer_loop_platform_result_record_json local-ai-reviewer clean "")"
  "$(reviewer_loop_platform_result_record_json codex-github needs_fixes "")"
  "$(reviewer_loop_platform_result_record_json bugbot needs_fixes "")"
)
platform_reviewed_heads=(
  "local-ai-reviewer:${_1651_descendant}"
  "codex-github:${_1651_descendant}"
  "bugbot:${_1651_ancestor}"
)
platform_blocking_outputs=(
  $'codex-github\036RESULT=needs_fixes\nBLOCKING_COUNT=1\nBLOCKING_1_PATH=a.ts\n'
  $'bugbot\036RESULT=needs_fixes\nBLOCKING_COUNT=1\nBLOCKING_1_PATH=b.ts\n'
)
_1651_recs="$(reviewer_loop_missed_finding_records '{"schema":"reviewer_loop_history.v1","entries":[]}' "$_1651_cfg" 1)"
run_test "1651_s16b_two_records" "2" "$(printf '%s\n' "$_1651_recs" | jq 'length')"
run_test "1651_s16b_codex_head" "$_1651_descendant" \
  "$(printf '%s\n' "$_1651_recs" | jq -r '.[] | select(.reviewer=="codex-github") | .reviewed_head')"
run_test "1651_s16b_bugbot_head" "$_1651_ancestor" \
  "$(printf '%s\n' "$_1651_recs" | jq -r '.[] | select(.reviewer=="bugbot") | .reviewed_head')"

# --- Scenario 11: unappendable history preserves prior block ---
_1651_prior_body="$(printf '%s\n' "<!-- reviewer-loop-history:v1 -->" '```json' '{"schema":"reviewer_loop_history.v1","history_status":"available","entries":[{"iteration":1,"result":"clean"}]}' '```')"
# wrap as details for extract
_1651_prior_full="$(printf '<details>\n<summary>Reviewer-loop history</summary>\n\n%s\n</details>\n' "$_1651_prior_body")"
# Force malformed so append_safe=0 but marker present
_1651_malformed="$(printf '%s\n' "### Automated Reviewer Loop Summary" "" "<details>" "<summary>x</summary>" "<!-- reviewer-loop-history:v1 -->" '```json' '{not-json' '```' "</details>")"
reviewer_loop_history_last_append_safe=1
# Invoke in the current shell so append_safe globals survive, then capture stdout.
_1651_out_file="$(mktemp)"
reviewer_loop_history_append_to_summary "### Automated Reviewer Loop Summary"$'\n'"body" "$_1651_malformed" clean "" "local-ai-reviewer" 0 0 0 "" 0 0 "" >"$_1651_out_file"
_1651_out="$(cat "$_1651_out_file")"
rm -f "$_1651_out_file"
run_test "1651_s11_append_safe_0" "0" "${reviewer_loop_history_last_append_safe}"
run_contains "1651_s11_preserves_malformed" '{not-json' "$_1651_out"
# Ensure stub with entries:[] is NOT written over it
if printf '%s\n' "$_1651_out" | grep -Fq '"entries": []'; then
  run_contains "1651_s11_malformed_still_present" '{not-json' "$_1651_out"
else
  run_test "1651_s11_no_empty_stub" "1" "1"
fi

# missing_history_json reason vocabulary
_1651_missing_marker="$(printf '%s\n' "### Automated Reviewer Loop Summary" "<!-- reviewer-loop-history:v1 -->" "no json block")"
reviewer_loop_history_payload_from_existing "$_1651_missing_marker" clean "" "x" 0 0 >/dev/null
# Assigned by the sourced pr-review-loop.sh function called above.
# shellcheck disable=SC2154
run_test "1651_s11a_missing_json_reason" "missing_history_json" \
  "${reviewer_loop_history_last_unavailable_reason}"

unset platform_result_records platform_reviewed_heads platform_blocking_outputs
unset platform_results_json missed_findings_json loop_head_sha
unset missed_finding_attribution_reports
unset _1651_ancestor _1651_descendant _1651_unrelated _1651_cfg
unset _1651_hist _1651_v _1651_recs _1651_rec _1651_line _1651_prior _1651_empty
unset _1651_long _1651_out _1651_paths _1651_r1 _1651_r2
unset _1651_lines _1651_total _1651_prior_body _1651_prior_full _1651_malformed
unset _1651_missing_marker _entry _field _st _i _p
unset -f _1651_verdict 2>/dev/null || true
eval "$_1651_real_ancestry"
unset _1651_real_ancestry
unset pr_number current_run_id unresolved_thread_count late_thread_count
unset expensive_gate_last_result strict_spec_recorded

echo "=== Area 1651 complete ==="

# ---------------------------------------------------------------------------
# Area 1653 — emit_prefixed_platform_output forwards REVIEW_* keys
# ---------------------------------------------------------------------------
echo "=== Area 1653: stage evidence forwarding ==="

_1653_platform_out="$(emit_prefixed_platform_output 1 "$(cat <<'KV'
RESULT=clean
REVIEW_STAGE=implementation
REVIEW_STAGE_SOURCE=branch+files
REVIEW_CHECKLISTS=Code Review Checklist,Workflow Policy Review Checklist
KV
)")"
run_test "1653_s13_review_stage" "PLATFORM_1_REVIEW_STAGE=implementation" \
  "$(printf '%s\n' "$_1653_platform_out" | grep '^PLATFORM_1_REVIEW_STAGE=' | head -n 1)"
run_test "1653_s13_review_source" "PLATFORM_1_REVIEW_STAGE_SOURCE=branch+files" \
  "$(printf '%s\n' "$_1653_platform_out" | grep '^PLATFORM_1_REVIEW_STAGE_SOURCE=' | head -n 1)"
run_test "1653_s13_review_lists" "PLATFORM_1_REVIEW_CHECKLISTS=Code Review Checklist,Workflow Policy Review Checklist" \
  "$(printf '%s\n' "$_1653_platform_out" | grep '^PLATFORM_1_REVIEW_CHECKLISTS=' | head -n 1)"
run_test "1653_s13_no_fabricated_key" "0" \
  "$(printf '%s\n' "$_1653_platform_out" | grep -c '^PLATFORM_1_Workflow Policy Review Checklist=' || true)"

echo "=== Area 1653 complete ==="

# ---------------------------------------------------------------------------
# Area 1656 — second local pass before ready-phase gate
# ---------------------------------------------------------------------------
echo "=== Area 1656: second local pass ==="

compare_mode=0
compare_verdicts=()

_1656_head="cccccccccccccccccccccccccccccccccccccccc"
_1656_ancestor="dddddddddddddddddddddddddddddddddddddddd"
_1656_unrelated="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
_1656_cfg=$'local-ai-reviewer\ncodex-github'

_1656_hist_clean_same() {
  jq -nc --arg head "$_1656_head" '{
    schema: "reviewer_loop_history.v1",
    entries: [{
      iteration: 1,
      platform_results: [{platform: "local-ai-reviewer", result: "clean", raw_result: "clean", raw_reason: ""}],
      reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $head, classification: "current"}]
    }]
  }'
}

_1656_hist_clean_ancestor() {
  jq -nc --arg head "$_1656_ancestor" --arg loop "$_1656_head" '{
    schema: "reviewer_loop_history.v1",
    entries: [{
      iteration: 1,
      platform_results: [{platform: "local-ai-reviewer", result: "clean", raw_result: "clean", raw_reason: ""}],
      reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $head, classification: "current"}]
    }]
  }'
}

_1656_hist_needs_fixes() {
  jq -nc --arg head "$_1656_head" '{
    schema: "reviewer_loop_history.v1",
    entries: [{
      iteration: 1,
      platform_results: [{platform: "local-ai-reviewer", result: "needs_fixes", raw_result: "needs_fixes", raw_reason: ""}],
      reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $head, classification: "current"}]
    }]
  }'
}

_1656_hist_no_local() {
  jq -nc '{
    schema: "reviewer_loop_history.v1",
    entries: [{
      iteration: 1,
      platform_results: [{platform: "codex-github", result: "clean", raw_result: "clean", raw_reason: ""}],
      reviewed_heads: [{platform: "codex-github", reviewed_head: "ffffffffffffffffffffffffffffffffffffffff", classification: "current"}]
    }]
  }'
}

run_test "1656_s1_not_required" "not_required" \
  "$(reviewer_loop_local_pass_required "$(_1656_hist_clean_same)" "$_1656_head" "$_1656_cfg")"
run_test "1656_s2_head_changed_ancestor" "head_changed" \
  "$(reviewer_loop_local_pass_required "$(_1656_hist_clean_ancestor)" "$_1656_head" "$_1656_cfg")"
run_test "1656_s3_head_changed_unrelated" "head_changed" \
  "$(reviewer_loop_local_pass_required "$(_1656_hist_clean_same | jq --arg u "$_1656_unrelated" '.entries[0].reviewed_heads[0].reviewed_head = $u')" "$_1656_head" "$_1656_cfg")"
run_test "1656_s4_prior_findings" "prior_findings" \
  "$(reviewer_loop_local_pass_required "$(_1656_hist_needs_fixes)" "$_1656_head" "$_1656_cfg")"
run_test "1656_s5_no_evidence" "no_evidence" \
  "$(reviewer_loop_local_pass_required "$(_1656_hist_no_local)" "$_1656_head" "$_1656_cfg")"
run_test "1656_s6_no_local_reviewer" "no_local_reviewer" \
  "$(reviewer_loop_local_pass_required "$(_1656_hist_no_local)" "$_1656_head" "codex-github")"
run_test "1656_s6b_no_local_reviewer_ignores_history" "no_local_reviewer" \
  "$(reviewer_loop_local_pass_required "$(_1656_hist_clean_same)" "$_1656_head" "codex-github")"

_1656_stale_head="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
_1656_fresh_head="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
platform_reviewed_heads=("local-ai-reviewer:${_1656_stale_head}" "codex-github:${_1656_head}")
platform_result_records=("$(reviewer_loop_platform_result_record_json local-ai-reviewer needs_fixes blocking)" \
  "$(reviewer_loop_platform_result_record_json codex-github clean "")")
compare_verdicts=("local-ai-reviewer" "unavailable" "codex-github" "clean")
reviewer_loop_replace_current_round_platform_record "local-ai-reviewer"
run_test "1656_s6c_replace_heads" "codex-github:${_1656_head}" \
  "$(printf '%s\n' "${platform_reviewed_heads[@]}")"
run_test "1656_s6c_replace_records" "1" \
  "$(printf '%s\n' "${platform_result_records[@]}" | jq -s 'map(.platform) | length')"
run_test "1656_s6c_replace_compare_verdicts" "codex-github clean" \
  "$(printf '%s %s\n' "${compare_verdicts[@]}")"
total_comment_count=0
total_blocking_count=0
total_suggestion_count=0
compare_mode=0
compare_verdicts=()
declare -a platform_peer_evidence=() aggregate_blocking_paths=() aggregate_blocking_findings=()
_sl_clean_out=$'RESULT=clean\nREVIEWED_HEAD='"${_1656_fresh_head}"$'\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n'
reviewer_loop_process_platform_output "local-ai-reviewer" 99 "$_sl_clean_out" 0 0
run_test "1656_s6c_latest_local_head" "${_1656_fresh_head}" \
  "$(printf '%s\n' "${platform_reviewed_heads[@]}" | awk -F: '/^local-ai-reviewer:/{h=$2} END{print h}')"
loop_head_sha="${_1656_fresh_head}"
platform_reviewed_heads=("local-ai-reviewer:${_1656_stale_head}" "local-ai-reviewer:${_1656_fresh_head}")
run_test "1656_s6d_expensive_gate_latest_head" "1" \
  "$(expensive_gate_local_ai_head_current "$_1656_fresh_head")"
platform_peer_evidence=("local-ai-reviewer|skipped|unavailable" "local-ai-reviewer|clean|")
run_test "1656_s6e_peer_evidence_latest" "clean|" \
  "$(expensive_gate_lookup_peer_evidence local-ai-reviewer)"
platform_peer_evidence=("local-ai-reviewer|skipped|unavailable")
reviewer_loop_replace_current_round_platform_record "local-ai-reviewer"
platform_peer_evidence+=("local-ai-reviewer|clean|")
run_test "1656_s6e_peer_replace_latest" "clean|" \
  "$(expensive_gate_lookup_peer_evidence local-ai-reviewer)"
platform_peer_evidence=("local-ai-reviewer|skipped|unavailable")
platform_blocking_outputs=("local-ai-reviewer"$'\036'$'RESULT=skipped\nREASON=unavailable\nCOMMENT_COUNT=1\nBLOCKING_COUNT=1\nSUGGESTION_COUNT=1\nBLOCKING_1_PATH=stale.md\nBLOCKING_1_BODY=stale\n')
total_comment_count=1
total_blocking_count=1
total_suggestion_count=1
reviewer_failed_required=1
aggregate_blocking_paths=("stale.md")
aggregate_blocking_findings=('{"path":"stale.md","body":"stale"}')
_sl_clean_out=$'RESULT=clean\nREVIEWED_HEAD='"${_1656_fresh_head}"$'\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n'
reviewer_loop_process_platform_output "local-ai-reviewer" 100 "$_sl_clean_out" 0 0 >/dev/null
run_test "1656_s6f_replacement_clears_reviewer_failed_required" "0" "$reviewer_failed_required"
run_test "1656_s6f_replacement_recomputes_comment_count" "0" "$total_comment_count"
run_test "1656_s6f_replacement_recomputes_blocking_count" "0" "$total_blocking_count"
run_test "1656_s6f_replacement_recomputes_suggestion_count" "0" "$total_suggestion_count"
run_test "1656_s6f_replacement_clears_blocking_paths" "0" "${#aggregate_blocking_paths[@]}"
run_test "1656_s6f_replacement_keeps_clean_peer" "clean|" \
  "$(expensive_gate_lookup_peer_evidence local-ai-reviewer)"
unset _1656_stale_head _1656_fresh_head platform_reviewed_heads platform_result_records _sl_clean_out loop_head_sha total_comment_count total_blocking_count total_suggestion_count platform_peer_evidence aggregate_blocking_paths aggregate_blocking_findings compare_mode compare_verdicts platform_blocking_outputs reviewer_failed_required

_1656_failed_hist="$(jq -nc --arg head "$_1656_head" '{
  schema: "reviewer_loop_history.v1",
  entries: [{iteration: 1, local_second_pass_failed_head: $head, result: "escalate", reason: "local_pass_unavailable"}]
}')"
run_test "1656_s8c_failed_head_count" "1" \
  "$(reviewer_loop_local_second_pass_failed_for_head "$_1656_failed_hist" "$_1656_head")"

run_test "1656_s7_gate_needs_fixes" "needs_fixes" \
  "$(reviewer_loop_second_local_pass_gate_result needs_fixes blocking | cut -f1)"
run_test "1656_s7_gate_needs_fixes_reason" "blocking" \
  "$(reviewer_loop_second_local_pass_gate_result needs_fixes blocking | cut -f2)"
run_test "1656_s7_gate_skipped" "escalate" \
  "$(reviewer_loop_second_local_pass_gate_result skipped unavailable | cut -f1)"
run_test "1656_s7_gate_skipped_reason" "local_pass_unavailable" \
  "$(reviewer_loop_second_local_pass_gate_result skipped unavailable | cut -f2)"

repo_review_platforms=(local-ai-reviewer codex-github)
platforms=(codex-github)
run_test "1656_s2b_repo_configured" "no_evidence" \
  "$(reviewer_loop_local_pass_required "$(_1656_hist_no_local)" "$_1656_head" "$(reviewer_loop_repo_configured_platforms)")"

# Scenario 5a / P8: shared processor key=value output is stable and omits second-pass keys
_1656_s5a_clean_out=$'RESULT=clean\nREVIEWED_HEAD='"$_1656_head"$'\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\nREASON=\n'
_1656_s5a_reset_processing_globals() {
  total_comment_count=0
  total_blocking_count=0
  total_suggestion_count=0
  reviewer_failed_required=0
  compare_mode=0
  compare_verdicts=()
  platform_peer_evidence=()
  platform_result_records=()
  platform_reviewed_heads=()
  platform_result_tokens=()
  platform_blocking_outputs=()
  aggregate_blocking_paths=()
  aggregate_blocking_findings=()
  platform_policy_status_notes=()
  aggregate_result="clean"
  aggregate_reason=""
  aggregate_output=""
  aggregate_status=0
  loop_head_sha="$_1656_head"
}
_1656_s5a_capture_output() {
  _1656_s5a_reset_processing_globals
  {
    reviewer_loop_process_platform_output "local-ai-reviewer" 1 "$_1656_s5a_clean_out" 0 1
  } 2>/dev/null
}
_1656_s5a_first="$(_1656_s5a_capture_output)"
_1656_s5a_second="$(_1656_s5a_capture_output)"
run_test "1656_s5a_extraction_byte_identical" "$_1656_s5a_first" "$_1656_s5a_second"
run_test "1656_s5a_no_second_pass_keys" "0" \
  "$(printf '%s' "$_1656_s5a_first" | grep -Ec '^(LOCAL_SECOND_PASS|LOCAL_SECOND_PASS_REASON)=' || true)"
run_test "1656_s5a_platform_result" "clean" \
  "$(printf '%s' "$_1656_s5a_first" | awk -F= '/^PLATFORM_1_RESULT=/{print $2; exit}')"
unset _1656_s5a_clean_out _1656_s5a_first _1656_s5a_second
unset -f _1656_s5a_reset_processing_globals _1656_s5a_capture_output 2>/dev/null || true

# Planted-violation proofs (REVIEW.md): wrong helpers live only in this harness.
_1656_pv_plant_p2_pass_required() {
  local payload="${1:-}" head="${2:-}" configured="${3:-}"
  local verdict outcome verdict_head
  if ! grep -Fxq -- 'local-ai-reviewer' <<<"$configured"; then
    printf 'no_local_reviewer\n'; return 0
  fi
  verdict="$(reviewer_loop_local_latest_verdict "$payload" "$configured")"
  outcome="$(printf '%s' "$verdict" | jq -r '.outcome // "unknown"')"
  verdict_head="$(printf '%s' "$verdict" | jq -r '.head_sha // ""')"
  case "$outcome" in
    not_configured) printf 'no_local_reviewer\n'; return 0 ;;
    not_yet_run|unknown) printf 'not_required\n'; return 0 ;;
    clean) ;;
    *) printf 'prior_findings\n'; return 0 ;;
  esac
  if [ -n "$head" ] && [ "$verdict_head" = "$head" ]; then
    printf 'not_required\n'
  else
    printf 'head_changed\n'
  fi
}
_1656_pv_plant_p10_pass_required() {
  local payload="${1:-}" head="${2:-}" configured="${3:-}"
  local verdict outcome verdict_head
  if ! grep -Fxq -- 'local-ai-reviewer' <<<"$configured"; then
    printf 'no_evidence\n'; return 0
  fi
  verdict="$(reviewer_loop_local_latest_verdict "$payload" "$configured")"
  outcome="$(printf '%s' "$verdict" | jq -r '.outcome // "unknown"')"
  verdict_head="$(printf '%s' "$verdict" | jq -r '.head_sha // ""')"
  case "$outcome" in
    not_configured|not_yet_run|unknown) printf 'no_evidence\n'; return 0 ;;
    clean) ;;
    *) printf 'prior_findings\n'; return 0 ;;
  esac
  if [ -n "$head" ] && [ "$verdict_head" = "$head" ]; then
    printf 'not_required\n'
  else
    printf 'head_changed\n'
  fi
}
run_test "1656_pv_P2_plant" "not_required" \
  "$(_1656_pv_plant_p2_pass_required "$(_1656_hist_no_local)" "$_1656_head" "$_1656_cfg")"
run_test "1656_pv_P2_correct" "no_evidence" \
  "$(reviewer_loop_local_pass_required "$(_1656_hist_no_local)" "$_1656_head" "$_1656_cfg")"
run_test "1656_pv_P2_plant_differs" "different" \
  "$( [ "$(_1656_pv_plant_p2_pass_required "$(_1656_hist_no_local)" "$_1656_head" "$_1656_cfg")" \
      != "$(reviewer_loop_local_pass_required "$(_1656_hist_no_local)" "$_1656_head" "$_1656_cfg")" ] \
     && echo different || echo same)"
run_test "1656_pv_P10_plant" "no_evidence" \
  "$(_1656_pv_plant_p10_pass_required "$(_1656_hist_no_local)" "$_1656_head" "codex-github")"
run_test "1656_pv_P10_correct" "no_local_reviewer" \
  "$(reviewer_loop_local_pass_required "$(_1656_hist_no_local)" "$_1656_head" "codex-github")"
run_test "1656_pv_P10_plant_differs" "different" \
  "$( [ "$(_1656_pv_plant_p10_pass_required "$(_1656_hist_no_local)" "$_1656_head" "codex-github")" \
      != "$(reviewer_loop_local_pass_required "$(_1656_hist_no_local)" "$_1656_head" "codex-github")" ] \
     && echo different || echo same)"
unset -f _1656_pv_plant_p2_pass_required _1656_pv_plant_p10_pass_required 2>/dev/null || true

# Guard validates pass-output REVIEWED_HEAD, not the first platform_reviewed_heads entry
_1656_fresh_head="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
run_test "1656_s5b_output_head_current" "current" \
  "$(reviewer_loop_head_evidence_classify "$_1656_fresh_head" "$_1656_fresh_head" | cut -d'|' -f1)"
run_test "1656_s5b_stale_head_not_current" "not-current" \
  "$(reviewer_loop_head_evidence_classify "dddddddddddddddddddddddddddddddddddddddd" "$_1656_fresh_head" | cut -d'|' -f1)"
unset _1656_fresh_head

# LOCAL_AI_* keys follow repository config, not invocation-filtered platforms[]
platforms=(codex-github)
repo_review_platforms=(local-ai-reviewer codex-github)
platform_reviewed_heads=("local-ai-reviewer:$_1656_head")
loop_head_sha="$_1656_head"
_1656_local_ai_keys="$(reviewer_loop_emit_local_ai_head_evidence_keys 2>/dev/null)"
run_test "1656_s2c_local_ai_configured" "1" "$(printf '%s\n' "$_1656_local_ai_keys" | awk -F= '/^LOCAL_AI_CONFIGURED=/{print $2; exit}')"
run_test "1656_s2c_local_ai_head_current" "1" "$(printf '%s\n' "$_1656_local_ai_keys" | awk -F= '/^LOCAL_AI_HEAD_CURRENT=/{print $2; exit}')"
unset platforms repo_review_platforms platform_reviewed_heads loop_head_sha _1656_local_ai_keys

# --- Guard integration (extracted function) ---
_1656_guard_head="ffffffffffffffffffffffffffffffffffffffff"
_1656_guard_hist_clean="$(jq -nc --arg head "$_1656_guard_head" '{
  schema: "reviewer_loop_history.v1",
  entries: [{
    iteration: 1,
    platform_results: [{platform: "local-ai-reviewer", result: "clean", raw_result: "clean", raw_reason: ""}],
    reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $head, classification: "current"}]
  }]
}')"
_1656_guard_hist_failed="$(jq -nc --arg head "$_1656_guard_head" '{
  schema: "reviewer_loop_history.v1",
  entries: [{iteration: 1, local_second_pass_failed_head: $head, result: "escalate"}]
}')"

reviewer_loop_prior_history_payload_from_pr() {
  if [ -n "${_1656_guard_hist_payload:-}" ]; then
    printf '%s\n' "$_1656_guard_hist_payload"
  else
    printf '%s\n' '{"schema":"reviewer_loop_history.v1","entries":[]}'
  fi
}

_1656_run_platform_review_calls=0
run_platform_review() {
  _1656_run_platform_review_calls=$((_1656_run_platform_review_calls + 1))
  case "${_1656_stub_pass_result:-clean}" in
    clean) printf 'RESULT=clean\nREVIEWED_HEAD=%s\n' "${loop_head_sha:-}" ;;
    clean_no_head) printf 'RESULT=clean\n' ;;
    skipped) printf 'RESULT=skipped\nREASON=unavailable\n' ;;
    needs_fixes) printf 'RESULT=needs_fixes\nREASON=blocking\nBLOCKING_COUNT=1\n' ;;
    needs_rerun) printf 'RESULT=needs_rerun\nREASON=stale_verdict\n' ;;
    escalate_pass) printf 'RESULT=escalate\nREASON=timeout\n' ;;
    waiting_pass) printf 'RESULT=waiting_on_reviewer\nREASON=reviewer-no-verdict-yet\nNO_VERDICT_YET=1\nWAIT_EXPIRED_DETAIL=stopped_at_budget\nPENDING_REVIEWER=local-ai-reviewer\nPENDING_REVIEW_HEAD_SHA=%s\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n' "${loop_head_sha:-}"; return 4 ;;
    unparseable) printf 'not-key=value-garbage\n' ;;
    *) printf 'RESULT=escalate\nREASON=unknown\n' ;;
  esac
  return 0
}

gh() {
  if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
    local _gh_head=""
    if [ "${_1656_stub_pr_head:-}" = "UNAVAILABLE" ]; then
      return 1
    fi
    if [ -n "${_1656_stub_pr_head:-}" ]; then
      _gh_head="$_1656_stub_pr_head"
    else
      _gh_head="${loop_head_sha:-}"
    fi
    if [[ "$*" == *"--jq"* ]]; then
      printf '%s\n' "$_gh_head"
    else
      printf '{"headRefOid":"%s"}\n' "$_gh_head"
    fi
    return 0
  fi
  command gh "$@"
}

_1656_reset_guard_globals() {
  phase_after_clean_enabled=1
  phase_after_clean_started=0
  local_second_pass=0
  local_second_pass_reason="not_required"
  local_second_pass_result=""
  local_second_pass_failed_head_record=""
  loop_head_sha="$_1656_guard_head"
  branch_name="refactor/1656-second-local-pass"
  pr_number=1693
  poll_interval=1
  max_wait=10
  platforms=(local-ai-reviewer codex-github)
  repo_review_platforms=(local-ai-reviewer codex-github)
  platform_result_records=()
  platform_reviewed_heads=()
  platform_peer_evidence=()
  platform_result_tokens=()
  platform_blocking_outputs=()
  aggregate_result="clean"
  aggregate_reason=""
  aggregate_output=""
  aggregate_status=0
  total_comment_count=0
  total_blocking_count=0
  total_suggestion_count=0
  reviewer_failed_required=0
  compare_mode=0
  compare_first_blocking_result=""
  _1656_run_platform_review_calls=0
  _1656_stub_pass_result="clean"
  _1656_stub_pr_head=""
}

# Scenario 4 / not_required: clean on loop_head_sha — no dispatch
_1656_reset_guard_globals
_1656_guard_hist_payload="$_1656_guard_hist_clean"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s4_guard_proceed" "0" "$_st"
run_test "1656_s4_guard_no_dispatch" "0" "$_1656_run_platform_review_calls"
run_test "1656_s4_guard_reason" "not_required" "$local_second_pass_reason"
run_test "1656_s4_guard_retains_head" "local-ai-reviewer:${_1656_guard_head}" \
  "$(printf '%s\n' "${platform_reviewed_heads[@]:-}")"
run_test "1656_s4_guard_retains_peer" "clean|retained_history" \
  "$(expensive_gate_lookup_peer_evidence local-ai-reviewer)"
run_test "1656_s4_guard_retains_result" "clean" \
  "$(printf '%s\n' "${platform_result_records[@]:-}" | jq -sr 'map(select(.platform == "local-ai-reviewer")) | last | .result // ""')"

# not_required must still re-read the live head before proceeding to ready-phase
_1656_moved_head="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
_1656_reset_guard_globals
_1656_guard_hist_payload="$_1656_guard_hist_clean"
_1656_stub_pr_head="$_1656_moved_head"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s4a_not_required_head_moved" "1" "$_st"
run_test "1656_s4a_not_required_no_dispatch" "0" "$_1656_run_platform_review_calls"
run_test "1656_s4a_not_required_reason" "head_moved_during_pass" "$local_second_pass_reason"
run_test "1656_s4a_not_required_aggregate" "head_moved_during_run" "$aggregate_reason"

_1656_reset_guard_globals
_1656_guard_hist_payload="$_1656_guard_hist_clean"
_1656_stub_pr_head="UNAVAILABLE"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s4b_not_required_unread_head" "1" "$_st"
run_test "1656_s4b_not_required_no_dispatch" "0" "$_1656_run_platform_review_calls"
run_test "1656_s4b_not_required_unavailable" "local_pass_unavailable" "$local_second_pass_reason"

_1656_reset_guard_globals
repo_review_platforms=(codex-github)
_1656_guard_hist_payload="$_1656_guard_hist_clean"
_1656_stub_pr_head="$_1656_moved_head"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s4c_no_local_head_moved" "1" "$_st"
run_test "1656_s4c_no_local_no_dispatch" "0" "$_1656_run_platform_review_calls"
run_test "1656_s4c_no_local_reason" "head_moved_during_pass" "$local_second_pass_reason"
run_test "1656_s4c_no_local_no_retained_peer" "" \
  "$(expensive_gate_lookup_peer_evidence local-ai-reviewer)"

# Scenario 8c: failed head refusal — no dispatch, escalate (P1/P9 restored)
_1656_reset_guard_globals
_1656_guard_hist_payload="$_1656_guard_hist_failed"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s8c_guard_refuse" "1" "$_st"
run_test "1656_s8c_guard_no_dispatch" "0" "$_1656_run_platform_review_calls"
run_test "1656_s8c_guard_escalate" "escalate" "$aggregate_result"
run_test "1656_s8c_guard_failed_reason" "failed_for_head" "$aggregate_reason"
run_test "1656_s8c_phase_not_started" "0" "$phase_after_clean_started"

# Prior ledger unavailable — close gate before dispatch (P9 / cross-invocation)
_1656_guard_hist_unavail='{"schema":"reviewer_loop_history.v1","history_status":"unavailable","history_unavailable_reason":"comment_read_failed","entries":[]}'
_1656_reset_guard_globals
_1656_guard_hist_payload="$_1656_guard_hist_unavail"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s8d_guard_unavail_blocked" "1" "$_st"
run_test "1656_s8d_guard_no_dispatch" "0" "$_1656_run_platform_review_calls"
run_test "1656_s8d_guard_unavailable" "local_pass_unavailable" "$local_second_pass_reason"
run_test "1656_s8d_phase_not_started" "0" "$phase_after_clean_started"
unset _1656_guard_hist_unavail

# Scenario 7a: skipped pass — escalate, phase not started
_1656_reset_guard_globals
_1656_guard_hist_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
_1656_stub_pass_result="skipped"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s7a_guard_blocked" "1" "$_st"
run_test "1656_s7a_guard_dispatch" "1" "$local_second_pass"
run_test "1656_s7a_guard_unavailable" "local_pass_unavailable" "$local_second_pass_reason"
run_test "1656_s7a_guard_escalate_reason" "local_pass_unavailable" "$aggregate_reason"
run_test "1656_s7a_phase_not_started" "0" "$phase_after_clean_started"

# Scenario 7: needs_fixes pass — gate closed, failed head recorded, phase not started
_1656_reset_guard_globals
_1656_guard_hist_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
_1656_stub_pass_result="needs_fixes"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s7_guard_blocked" "1" "$_st"
run_test "1656_s7_guard_needs_fixes" "needs_fixes" "$aggregate_result"
run_test "1656_s7_guard_failed_head" "$_1656_guard_head" "$local_second_pass_failed_head_record"
run_test "1656_s7_phase_not_started" "0" "$phase_after_clean_started"

# Scenario 7b: needs_rerun pass — unavailable escalation, phase not started
_1656_reset_guard_globals
_1656_guard_hist_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
_1656_stub_pass_result="needs_rerun"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s7b_guard_blocked" "1" "$_st"
run_test "1656_s7b_guard_unavailable" "local_pass_unavailable" "$local_second_pass_reason"
run_test "1656_s7b_guard_escalate" "escalate" "$aggregate_result"
run_test "1656_s7b_phase_not_started" "0" "$phase_after_clean_started"

# Escalate pass — unavailable escalation through shared processor mapping
_1656_reset_guard_globals
_1656_guard_hist_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
_1656_stub_pass_result="escalate_pass"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s7c_guard_blocked" "1" "$_st"
run_test "1656_s7c_guard_escalate" "escalate" "$aggregate_result"
run_test "1656_s7c_guard_timeout" "timeout" "$aggregate_reason"
run_test "1656_s7c_guard_telemetry" "local_pass_unavailable" "$local_second_pass_reason"
run_test "1656_s7c_phase_not_started" "0" "$phase_after_clean_started"

# #1789 (T2.9): a second local pass with no verdict yet — aggregate waiting,
# no failed-for-head record, not local_pass_unavailable, label not required.
_1656_reset_guard_globals
_1656_guard_hist_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
_1656_stub_pass_result="waiting_pass"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1789_T2.9_second_pass_waiting_blocked" "1" "$_st"
run_test "1789_T2.9_second_pass_waiting_aggregate" "waiting_on_reviewer" "$aggregate_result"
run_test "1789_T2.9_second_pass_waiting_reason" "reviewer-no-verdict-yet" "$aggregate_reason"
run_test "1789_T2.9_second_pass_waiting_status" "4" "$aggregate_status"
run_test "1789_T2.9_second_pass_waiting_pending_reviewer" "local-ai-reviewer" \
  "$(kv_value_default PENDING_REVIEWER "$aggregate_output" "")"
run_test "1789_T2.9_second_pass_waiting_no_failed_head" "" "$local_second_pass_failed_head_record"
run_test "1789_T2.9_second_pass_waiting_label_not_required" "0" "$reviewer_failed_required"
run_test "1789_T2.9_second_pass_waiting_ledger_no_verdict_yet" "no_verdict_yet" \
  "$(printf '%s\n' "${platform_result_records[@]:-}" | jq -sr 'map(select(.platform == "local-ai-reviewer")) | last | .result // ""')"
run_test "1789_T2.9_second_pass_waiting_phase_not_started" "0" "$phase_after_clean_started"
run_test "1789_T2.9_gate_result_waiting" "waiting_on_reviewer|reviewer-no-verdict-yet" \
  "$(reviewer_loop_second_local_pass_gate_result waiting_on_reviewer reviewer-no-verdict-yet | tr '\t' '|')"

# Unparseable pass output — unavailable escalation (P15 / scenario 7b shape)
_1656_reset_guard_globals
_1656_guard_hist_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
_1656_stub_pass_result="unparseable"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s7d_guard_blocked" "1" "$_st"
run_test "1656_s7d_guard_unavailable" "local_pass_unavailable" "$local_second_pass_reason"
run_test "1656_s7d_phase_not_started" "0" "$phase_after_clean_started"

# Clean pass without REVIEWED_HEAD — must not proceed (current-head evidence contract)
_1656_reset_guard_globals
_1656_guard_hist_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
_1656_stub_pass_result="clean_no_head"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s3c_guard_no_reviewed_head" "1" "$_st"
run_test "1656_s3c_guard_reason" "local_pass_unavailable" "$local_second_pass_reason"
run_test "1656_s3c_guard_unavailable" "local_pass_unavailable" "$aggregate_reason"
run_test "1656_s3c_phase_not_started" "0" "$phase_after_clean_started"

# Scenario 3a: head moves during clean pass — needs_fixes, head_moved_during_run
_1656_moved_head="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
_1656_reset_guard_globals
_1656_guard_hist_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
_1656_stub_pr_head="$_1656_moved_head"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s3a_guard_blocked" "1" "$_st"
run_test "1656_s3a_guard_dispatch" "1" "$local_second_pass"
run_test "1656_s3a_guard_reason" "head_moved_during_pass" "$local_second_pass_reason"
run_test "1656_s3a_aggregate_reason" "head_moved_during_run" "$aggregate_reason"
run_test "1656_s3a_phase_not_started" "0" "$phase_after_clean_started"

# gh head re-read unavailable after clean pass — must not proceed
_1656_reset_guard_globals
_1656_guard_hist_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
_1656_stub_pr_head="UNAVAILABLE"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s3d_guard_blocked" "1" "$_st"
run_test "1656_s3d_guard_unavailable" "local_pass_unavailable" "$local_second_pass_reason"
run_test "1656_s3d_no_failed_head_record" "" "$local_second_pass_failed_head_record"
run_test "1656_s3d_phase_not_started" "0" "$phase_after_clean_started"

# Scenarios 9/10 (P3): second pass must not increment cycle counters
_1656_reset_guard_globals
cycle_count=2
lifetime_cycle_count=5
_1656_guard_hist_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
_1656_stub_pass_result="clean"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s9_dispatch_cycle_count" "2" "$cycle_count"
run_test "1656_s9_dispatch_lifetime_count" "5" "$lifetime_cycle_count"

# Dispatched clean success path proceeds when gh --jq returns raw head SHA
_1656_reset_guard_globals
_1656_guard_hist_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
_1656_stub_pass_result="clean"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s5_guard_clean_proceed" "0" "$_st"
run_test "1656_s5_guard_clean_dispatch" "1" "$local_second_pass"
run_test "1656_s5_guard_clean_reason" "no_evidence" "$local_second_pass_reason"

_1656_reset_guard_globals
cycle_count=4
lifetime_cycle_count=7
_1656_guard_hist_payload="$_1656_guard_hist_failed"
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s10_refuse_cycle_count" "4" "$cycle_count"
run_test "1656_s10_refuse_lifetime_count" "7" "$lifetime_cycle_count"
unset cycle_count lifetime_cycle_count

# Scenario 13: no ready-phase — guard no-op
_1656_reset_guard_globals
phase_after_clean_enabled=0
_1656_guard_hist_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
reviewer_loop_second_local_pass_before_ready_gate 1693 && _st=0 || _st=$?
run_test "1656_s13_guard_noop" "0" "$_st"
run_test "1656_s13_guard_no_dispatch" "0" "$_1656_run_platform_review_calls"

unset _1656_guard_head _1656_guard_hist_clean _1656_guard_hist_failed _1656_guard_hist_payload
unset _1656_run_platform_review_calls _1656_stub_pass_result _1656_stub_pr_head _1656_moved_head _st
unset -f reviewer_loop_prior_history_payload_from_pr run_platform_review 2>/dev/null || true
if declare -F gh >/dev/null 2>&1; then
  unset -f gh
fi

unset _1656_head _1656_ancestor _1656_unrelated _1656_cfg _1656_failed_hist
unset repo_review_platforms platforms
unset -f _1656_hist_clean_same _1656_hist_clean_ancestor _1656_hist_needs_fixes _1656_hist_no_local 2>/dev/null || true

echo "=== Area 1656 complete ==="

# ---------------------------------------------------------------------------
# Area 1692: per-head reviewer staging
# ---------------------------------------------------------------------------
#
# The loop must not re-dispatch a reviewer that the persisted ledger already
# records clean on the current head, must still dispatch on every other
# evidence state, and must never let a later-phase reviewer's clean stand in
# for an earlier-phase reviewer that is not clean on the same head.
echo ""
echo "=== Area 1692: per-head reviewer staging ==="

_1692_head="1111111111111111111111111111111111111111"
_1692_other="2222222222222222222222222222222222222222"

# <platform> <result> <head> — one-entry ledger.
_1692_hist_one() {
  jq -nc --arg platform "$1" --arg result "$2" --arg head "$3" '{
    schema: "reviewer_loop_history.v1",
    entries: [{
      iteration: 1,
      platform_results: [{platform: $platform, result: $result, raw_result: $result, raw_reason: ""}],
      reviewed_heads: [{platform: $platform, reviewed_head: $head, state: "current", reason: ""}]
    }]
  }'
}

# Scenario A: local clean on head H → skip local on later cycles of H.
run_test "1692_sA_clean_current" "clean_current" \
  "$(reviewer_loop_platform_clean_for_head "$(_1692_hist_one local-ai-reviewer clean "$_1692_head")" local-ai-reviewer "$_1692_head")"

# Scenario B: new head after ready-phase findings → the reviewer runs again.
run_test "1692_sB_head_changed" "head_changed" \
  "$(reviewer_loop_platform_clean_for_head "$(_1692_hist_one local-ai-reviewer clean "$_1692_other")" local-ai-reviewer "$_1692_head")"

# Scenario C: later-tool clean + earlier tool not clean on the same head must
# not read as loop-complete. bugbot (on_ready) is clean on H, local
# (on_draft) is not: the skip refuses for local, and the #1656 ready gate
# still owes a pass, so the ready phase cannot proceed on bugbot's evidence.
_1692_mixed="$(jq -nc --arg head "$_1692_head" '{
  schema: "reviewer_loop_history.v1",
  entries: [{
    iteration: 1,
    platform_results: [
      {platform: "local-ai-reviewer", result: "needs_fixes", raw_result: "needs_fixes", raw_reason: "blocking"},
      {platform: "bugbot", result: "clean", raw_result: "clean", raw_reason: ""}
    ],
    reviewed_heads: [
      {platform: "local-ai-reviewer", reviewed_head: $head, state: "current", reason: ""},
      {platform: "bugbot", reviewed_head: $head, state: "current", reason: ""}
    ]
  }]
}')"
run_test "1692_sC_later_tool_clean_current" "clean_current" \
  "$(reviewer_loop_platform_clean_for_head "$_1692_mixed" bugbot "$_1692_head")"
run_test "1692_sC_earlier_tool_not_clean" "not_clean" \
  "$(reviewer_loop_platform_clean_for_head "$_1692_mixed" local-ai-reviewer "$_1692_head")"
run_test "1692_sC_ready_gate_still_owes_pass" "prior_findings" \
  "$(reviewer_loop_local_pass_required "$_1692_mixed" "$_1692_head" $'local-ai-reviewer\n')"

# Newest entry governs: a clean on H followed by needs_fixes on H dispatches.
_1692_regressed="$(jq -nc --arg head "$_1692_head" '{
  schema: "reviewer_loop_history.v1",
  entries: [
    {iteration: 1,
     platform_results: [{platform: "pr-agent", result: "clean", raw_result: "clean", raw_reason: ""}],
     reviewed_heads: [{platform: "pr-agent", reviewed_head: $head, state: "current", reason: ""}]},
    {iteration: 2,
     platform_results: [{platform: "pr-agent", result: "needs_fixes", raw_result: "needs_fixes", raw_reason: "blocking"}],
     reviewed_heads: [{platform: "pr-agent", reviewed_head: $head, state: "current", reason: ""}]}
  ]
}')"
run_test "1692_sD_newest_entry_governs" "not_clean" \
  "$(reviewer_loop_platform_clean_for_head "$_1692_regressed" pr-agent "$_1692_head")"

# Unknown is never clean: absent platform, absent reviewed head, empty and
# unparseable payloads, and empty arguments all dispatch.
run_test "1692_sE_absent_platform" "no_evidence" \
  "$(reviewer_loop_platform_clean_for_head "$(_1692_hist_one pr-agent clean "$_1692_head")" bugbot "$_1692_head")"
run_test "1692_sE_no_reviewed_head" "head_changed" \
  "$(reviewer_loop_platform_clean_for_head "$(_1692_hist_one pr-agent clean "$_1692_head" | jq -c 'del(.entries[0].reviewed_heads)')" pr-agent "$_1692_head")"
run_test "1692_sE_empty_payload" "no_evidence" \
  "$(reviewer_loop_platform_clean_for_head "" pr-agent "$_1692_head")"
run_test "1692_sE_unparseable_payload" "no_evidence" \
  "$(reviewer_loop_platform_clean_for_head "not-json" pr-agent "$_1692_head")"
run_test "1692_sE_empty_head" "no_evidence" \
  "$(reviewer_loop_platform_clean_for_head "$(_1692_hist_one pr-agent clean "$_1692_head")" pr-agent "")"
run_test "1692_sE_empty_platform" "no_evidence" \
  "$(reviewer_loop_platform_clean_for_head "$(_1692_hist_one pr-agent clean "$_1692_head")" "" "$_1692_head")"
run_test "1692_sE_skipped_is_not_clean" "not_clean" \
  "$(reviewer_loop_platform_clean_for_head "$(_1692_hist_one pr-agent skipped "$_1692_head")" pr-agent "$_1692_head")"

# The replayed verdict carries the same evidence a dispatch would have carried.
_1692_skip_out="$(reviewer_loop_stage_skip_output "$_1692_head")"
run_test "1692_sF_skip_output_result" "clean" \
  "$(printf '%s\n' "$_1692_skip_out" | awk -F= '/^RESULT=/{print $2; exit}')"
run_test "1692_sF_skip_output_reason" "already_clean_current_head" \
  "$(printf '%s\n' "$_1692_skip_out" | awk -F= '/^REASON=/{print $2; exit}')"
run_test "1692_sF_skip_output_reviewed_head" "$_1692_head" \
  "$(printf '%s\n' "$_1692_skip_out" | awk -F= '/^REVIEWED_HEAD=/{print $2; exit}')"
run_test "1692_sF_skip_output_no_blocking" "0" \
  "$(printf '%s\n' "$_1692_skip_out" | awk -F= '/^BLOCKING_COUNT=/{print $2; exit}')"

_1692_reset_processing_globals() {
  total_comment_count=0
  total_blocking_count=0
  total_suggestion_count=0
  reviewer_failed_required=0
  compare_mode=0
  compare_verdicts=()
  platform_peer_evidence=()
  platform_result_records=()
  platform_reviewed_heads=()
  platform_result_tokens=()
  platform_blocking_outputs=()
  aggregate_blocking_paths=()
  aggregate_blocking_findings=()
  platform_policy_status_notes=()
  aggregate_result="skipped"
  aggregate_reason=""
  aggregate_output=""
  aggregate_status=0
  aggregate_advisory_labels=""
  reviewer_loop_platform_loop_should_break=0
  loop_head_sha="$_1692_head"
}
_1692_reset_processing_globals
reviewer_loop_process_platform_output "local-ai-reviewer" 1 "$_1692_skip_out" 0 1 >/dev/null 2>&1
run_test "1692_sF_replayed_aggregate" "clean" "$aggregate_result"
run_test "1692_sF_replayed_no_break" "0" "$reviewer_loop_platform_loop_should_break"
run_test "1692_sF_replayed_reviewed_head" "local-ai-reviewer:${_1692_head}" \
  "$(printf '%s\n' "${platform_reviewed_heads[@]}")"
run_test "1692_sF_replayed_peer_evidence" "clean|already_clean_current_head" \
  "$(expensive_gate_lookup_peer_evidence local-ai-reviewer)"
run_test "1692_sF_replayed_peer_acceptable" "acceptable" \
  "$(expensive_gate_peer_evidence_acceptable clean already_clean_current_head && echo acceptable || echo refused)"
run_test "1692_sF_replayed_ledger_record" "clean" \
  "$(printf '%s\n' "${platform_result_records[@]}" | jq -r 'select(.platform == "local-ai-reviewer") | .result')"
run_test "1692_sF_replayed_no_reviewer_failed" "0" "$reviewer_failed_required"
run_test "1692_sF_replayed_token" "local-ai-reviewer:clean (already clean on head)" \
  "$(printf '%s\n' "${platform_result_tokens[@]}")"
run_test "1692_sF_replayed_head_current" "1" \
  "$(expensive_gate_local_ai_head_current "$_1692_head")"

# Check 0.6 (#1648) sees the replayed head, so a skipped local reviewer still
# produces current-head evidence rather than the empty LOCAL_AI_HEAD_CURRENT
# that refuses readiness.
_1692_saved_platforms=()
if declare -p platforms >/dev/null 2>&1 && [ "${#platforms[@]}" -gt 0 ]; then
  _1692_saved_platforms=("${platforms[@]}")
fi
platforms=(local-ai-reviewer)
repo_review_platforms=(local-ai-reviewer)
_1692_local_ai_keys="$(reviewer_loop_emit_local_ai_head_evidence_keys 2>/dev/null)"
run_test "1692_sF_check06_configured" "1" \
  "$(printf '%s\n' "$_1692_local_ai_keys" | awk -F= '/^LOCAL_AI_CONFIGURED=/{print $2; exit}')"
run_test "1692_sF_check06_head_current" "1" \
  "$(printf '%s\n' "$_1692_local_ai_keys" | awk -F= '/^LOCAL_AI_HEAD_CURRENT=/{print $2; exit}')"
run_test "1692_sF_check06_reviewed_head" "$_1692_head" \
  "$(printf '%s\n' "$_1692_local_ai_keys" | awk -F= '/^LOCAL_AI_REVIEWED_HEAD=/{print $2; exit}')"

# The composed current-round payload makes the #1656 ready gate a no-op, so a
# skipped local reviewer is not immediately re-dispatched by the second pass.
_1692_composed="$(reviewer_loop_compose_current_round_payload '{"schema":"reviewer_loop_history.v1","entries":[]}' 1)"
run_test "1692_sG_second_pass_not_required" "not_required" \
  "$(reviewer_loop_local_pass_required "$_1692_composed" "$_1692_head" $'local-ai-reviewer\n')"
# ...and a head change after the skip still owes a pass.
run_test "1692_sG_second_pass_after_new_head" "head_changed" \
  "$(reviewer_loop_local_pass_required "$_1692_composed" "$_1692_other" $'local-ai-reviewer\n')"

# Boundary and blank-input coverage for the predicate.
run_test "1692_sE_zero_entries" "no_evidence" \
  "$(reviewer_loop_platform_clean_for_head '{"schema":"reviewer_loop_history.v1","entries":[]}' pr-agent "$_1692_head")"
run_test "1692_sE_whitespace_payload" "no_evidence" \
  "$(reviewer_loop_platform_clean_for_head "   " pr-agent "$_1692_head")"
run_test "1692_sE_whitespace_platform" "no_evidence" \
  "$(reviewer_loop_platform_clean_for_head "$(_1692_hist_one pr-agent clean "$_1692_head")" "   " "$_1692_head")"
# Quoting safety: a platform name carrying spaces and glob characters must be
# matched literally, never word-split or expanded.
_1692_odd_platform='weird platform *[name]'
run_test "1692_sE_odd_platform_name_clean" "clean_current" \
  "$(reviewer_loop_platform_clean_for_head "$(_1692_hist_one "$_1692_odd_platform" clean "$_1692_head")" "$_1692_odd_platform" "$_1692_head")"
run_test "1692_sE_odd_platform_name_no_glob_match" "no_evidence" \
  "$(reviewer_loop_platform_clean_for_head "$(_1692_hist_one "$_1692_odd_platform" clean "$_1692_head")" 'weird platform x' "$_1692_head")"
unset _1692_odd_platform

# Stage-skip resolution: every disable condition, and the enabled path.
_1692_stage_hist='{"schema":"reviewer_loop_history.v1","entries":[]}'
_1692_stage_hist_unavailable='{"schema":"reviewer_loop_history.v1","history_status":"unavailable","history_unavailable_reason":"comment_fetch_failed","entries":[]}'
_1692_stage_payload_to_return="$_1692_stage_hist"
reviewer_loop_prior_history_payload_from_pr() { printf '%s\n' "$_1692_stage_payload_to_return"; }
_1692_reset_stage_globals() {
  platforms=(local-ai-reviewer bugbot)
  compare_mode=0
  platform_selection_explicit=0
  loop_head_sha="$_1692_head"
  _1692_stage_payload_to_return="$_1692_stage_hist"
  unset PR_REVIEW_LOOP_DISABLE_STAGE_SKIP
}

_1692_reset_stage_globals
reviewer_loop_stage_skip_resolve 1692
# stage_skip_* are assigned by the sourced reviewer_loop_stage_skip_resolve.
# shellcheck disable=SC2154
run_test "1692_sH_enabled" "1" "$stage_skip_enabled"
# shellcheck disable=SC2154
run_test "1692_sH_enabled_no_reason" "" "$stage_skip_disabled_reason"

_1692_reset_stage_globals
PR_REVIEW_LOOP_DISABLE_STAGE_SKIP=1
reviewer_loop_stage_skip_resolve 1692
run_test "1692_sH_disabled_by_env" "disabled_by_env" "$stage_skip_disabled_reason"
run_test "1692_sH_disabled_by_env_flag" "0" "$stage_skip_enabled"
unset PR_REVIEW_LOOP_DISABLE_STAGE_SKIP

# An empty or absent value is not "1" and must not disable staging.
_1692_reset_stage_globals
PR_REVIEW_LOOP_DISABLE_STAGE_SKIP=""
reviewer_loop_stage_skip_resolve 1692
run_test "1692_sH_empty_env_does_not_disable" "1" "$stage_skip_enabled"
unset PR_REVIEW_LOOP_DISABLE_STAGE_SKIP

_1692_reset_stage_globals
compare_mode=1
reviewer_loop_stage_skip_resolve 1692
run_test "1692_sH_compare_mode" "compare_mode" "$stage_skip_disabled_reason"

_1692_reset_stage_globals
platform_selection_explicit=1
reviewer_loop_stage_skip_resolve 1692
run_test "1692_sH_explicit_platform" "explicit_platform_selection" "$stage_skip_disabled_reason"

_1692_reset_stage_globals
loop_head_sha=""
reviewer_loop_stage_skip_resolve 1692
run_test "1692_sH_head_unknown" "head_unknown" "$stage_skip_disabled_reason"

_1692_reset_stage_globals
reviewer_loop_stage_skip_resolve ""
run_test "1692_sH_no_pr" "head_unknown" "$stage_skip_disabled_reason"

_1692_reset_stage_globals
platforms=()
reviewer_loop_stage_skip_resolve 1692
run_test "1692_sH_no_platforms" "head_unknown" "$stage_skip_disabled_reason"

_1692_reset_stage_globals
_1692_stage_payload_to_return="$_1692_stage_hist_unavailable"
reviewer_loop_stage_skip_resolve 1692
run_test "1692_sH_history_unavailable" "history_unavailable" "$stage_skip_disabled_reason"
run_test "1692_sH_history_unavailable_flag" "0" "$stage_skip_enabled"
# shellcheck disable=SC2154
run_test "1692_sH_history_unavailable_payload_cleared" "" "$stage_skip_history_payload"

unset _1692_stage_hist _1692_stage_hist_unavailable _1692_stage_payload_to_return
unset stage_skip_enabled stage_skip_disabled_reason stage_skip_history_payload
unset compare_mode platform_selection_explicit loop_head_sha
unset -f reviewer_loop_prior_history_payload_from_pr _1692_reset_stage_globals 2>/dev/null || true

# Planted-violation proofs (REVIEW.md): the wrong helpers live only in this
# harness. Each plant is a formulation that passes a naive reading of the
# issue but breaks a stated contract, paired with the correct helper.
#
# P1 — deny-list instead of fail-closed: skip unless the newest result is
# explicitly not clean. Missing evidence then reads as "already clean" and the
# reviewer is never dispatched on a head nobody reviewed.
_1692_pv_plant_p1_deny_list() {
  local payload="${1:-}" platform="${2:-}" head="${3:-}"
  local state
  state="$(reviewer_loop_platform_clean_for_head "$payload" "$platform" "$head")"
  case "$state" in
    not_clean) printf 'not_clean\n' ;;
    *) printf 'clean_current\n' ;;
  esac
}
run_test "1692_pv_P1_plant" "clean_current" \
  "$(_1692_pv_plant_p1_deny_list "$(_1692_hist_one pr-agent clean "$_1692_head")" bugbot "$_1692_head")"
run_test "1692_pv_P1_correct" "no_evidence" \
  "$(reviewer_loop_platform_clean_for_head "$(_1692_hist_one pr-agent clean "$_1692_head")" bugbot "$_1692_head")"
run_test "1692_pv_P1_plant_differs" "different" \
  "$( [ "$(_1692_pv_plant_p1_deny_list "$(_1692_hist_one pr-agent clean "$_1692_head")" bugbot "$_1692_head")" \
      != "$(reviewer_loop_platform_clean_for_head "$(_1692_hist_one pr-agent clean "$_1692_head")" bugbot "$_1692_head")" ] \
     && echo different || echo same)"

# P2 — read the reviewed head from any entry instead of the entry that carries
# the governing verdict. A stale clean on an old head then borrows a newer
# entry's head evidence and skips a reviewer that never saw this commit.
_1692_pv_plant_p2_any_entry_head() {
  local payload="${1:-}" platform="${2:-}" head="${3:-}"
  local outcome verdict_head
  outcome="$(printf '%s' "$payload" | jq -r --arg p "$platform" '
    [(.entries // [])[] | . as $e | ((.platform_results // [])[] | select(.platform == $p)
      | {outcome: (.result // "unknown"), iteration: ($e.iteration // 0)})]
    | if length > 0 then (sort_by(.iteration) | last | .outcome) else "not_yet_run" end')"
  verdict_head="$(printf '%s' "$payload" | jq -r --arg p "$platform" '
    [(.entries // [])[] | (.reviewed_heads // [])[] | select(.platform == $p) | .reviewed_head // ""]
    | map(select(. != "")) | last // ""')"
  case "$outcome" in
    clean) ;;
    not_yet_run|unknown) printf 'no_evidence\n'; return 0 ;;
    *) printf 'not_clean\n'; return 0 ;;
  esac
  if [ -n "$verdict_head" ] && [ "$verdict_head" = "$head" ]; then
    printf 'clean_current\n'
  else
    printf 'head_changed\n'
  fi
}
# Entry 1: clean on the OLD head. Entry 2: a later round where the same
# platform only reported a head (no verdict) on the CURRENT head.
_1692_pv_borrowed="$(jq -nc --arg old "$_1692_other" --arg new "$_1692_head" '{
  schema: "reviewer_loop_history.v1",
  entries: [
    {iteration: 1,
     platform_results: [{platform: "pr-agent", result: "clean", raw_result: "clean", raw_reason: ""}],
     reviewed_heads: [{platform: "pr-agent", reviewed_head: $old, state: "current", reason: ""}]},
    {iteration: 2,
     platform_results: [],
     reviewed_heads: [{platform: "pr-agent", reviewed_head: $new, state: "current", reason: ""}]}
  ]
}')"
run_test "1692_pv_P2_plant" "clean_current" \
  "$(_1692_pv_plant_p2_any_entry_head "$_1692_pv_borrowed" pr-agent "$_1692_head")"
run_test "1692_pv_P2_correct" "head_changed" \
  "$(reviewer_loop_platform_clean_for_head "$_1692_pv_borrowed" pr-agent "$_1692_head")"
run_test "1692_pv_P2_plant_differs" "different" \
  "$( [ "$(_1692_pv_plant_p2_any_entry_head "$_1692_pv_borrowed" pr-agent "$_1692_head")" \
      != "$(reviewer_loop_platform_clean_for_head "$_1692_pv_borrowed" pr-agent "$_1692_head")" ] \
     && echo different || echo same)"
unset _1692_pv_borrowed
unset -f _1692_pv_plant_p1_deny_list _1692_pv_plant_p2_any_entry_head 2>/dev/null || true

unset _1692_composed _1692_local_ai_keys _1692_skip_out _1692_mixed _1692_regressed
unset platforms repo_review_platforms
if [ "${#_1692_saved_platforms[@]}" -gt 0 ]; then
  platforms=("${_1692_saved_platforms[@]}")
fi
unset _1692_saved_platforms
unset total_comment_count total_blocking_count total_suggestion_count reviewer_failed_required
unset compare_mode compare_verdicts platform_peer_evidence platform_result_records
unset platform_reviewed_heads platform_result_tokens platform_blocking_outputs
unset aggregate_blocking_paths aggregate_blocking_findings platform_policy_status_notes
unset aggregate_result aggregate_reason aggregate_output aggregate_status aggregate_advisory_labels
unset reviewer_loop_platform_loop_should_break loop_head_sha
unset _1692_head _1692_other
unset -f _1692_hist_one _1692_reset_processing_globals 2>/dev/null || true

echo "=== Area 1692 complete ==="

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
