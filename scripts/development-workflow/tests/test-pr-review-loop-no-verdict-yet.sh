#!/usr/bin/env bash
# test-pr-review-loop-no-verdict-yet.sh — pr-review-loop.sh harness: reviewer
# wait budgets and the no-verdict-yet outcome (#1789).
# duration: 65
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
#   Area 1789: reviewer no verdict yet
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop-no-verdict-yet.sh [--area <name>]... [--list-areas]
# No external tooling required beyond bash, git, and jq (git only locates the
# repository root at startup; mock gh commands replace all network calls).
#
# Exit code: 0 if all tests pass, 1 if any test fails, 2 on a usage error.
#
# Many assignments here set pr-review-loop.sh globals that the functions under
# test read. ShellCheck does not follow that source, so each such assignment
# carries its own `# shellcheck disable=SC2034` with the reason inline.

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
# Area 1789: reviewer no verdict yet (#1789)
# Phase 1 — per-platform wait budgets (plan D1, D2, D6, D7, D13, D14): the
# review.wait_budgets config reader, the budget and poll-interval resolvers,
# and --max-wait validation (T1.1–T1.10).
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 1789: reviewer no verdict yet ==="

_1789_dir="$(mktemp -d)"
_1789_saved_branch="${branch_name-}"
_1789_saved_config="${config_file-}"
_1789_saved_changed="${changed_files_count-}"
unset max_wait_override poll_interval_override PR_REVIEW_LOOP_DOC_MAX_WAIT
unset CODEX_GITHUB_MAX_WAIT CODEX_GITHUB_POLL_INTERVAL
unset large_diff_threshold large_diff_max_wait
changed_files_count=-1
branch_name="feature/1789-x"

# _1789_cfg <name> <yaml body>: writes a config file and prints its path.
_1789_cfg() {
  printf '%s\n' "$2" > "$_1789_dir/$1.yaml"
  printf '%s\n' "$_1789_dir/$1.yaml"
}

_1789_none_cfg="$(_1789_cfg none 'review:
  max_cycles: 10')"

# --- T1.1: no override, no config → D2 default for each of the twelve platforms
config_file="$_1789_none_cfg"
for _1789_p in greptile devin coderabbit coderabbit-cli local-ai-reviewer pr-agent claude-code-action copilot haystack ronda; do
  run_test "1789_T1.1_default_${_1789_p}" "1200 default none" "$(reviewer_wait_budget_resolve "$_1789_p")"
done
run_test "1789_T1.1_default_bugbot" "2400 default none" "$(reviewer_wait_budget_resolve bugbot)"
run_test "1789_T1.1_default_codex-github" "1800 default none" "$(reviewer_wait_budget_resolve codex-github)"
run_test "1789_T1.1_twelve_supported_platforms" "12" "$(printf '%s\n' $REVIEWER_LOOP_SUPPORTED_PLATFORMS | grep -c .)"
config_file="$_1789_dir/missing.yaml"
run_test "1789_T1.1_missing_config_file_default" "2400 default none" "$(reviewer_wait_budget_resolve bugbot 2>/dev/null)"

# --- T1.2: valid configured value → configured; --max-wait override wins for every platform
config_file="$(_1789_cfg valid 'review:
  wait_budgets:
    bugbot: 2700')"
run_test "1789_T1.2_bugbot_configured" "2700 configured none" "$(reviewer_wait_budget_resolve bugbot)"
run_test "1789_T1.2_unconfigured_peer_default" "1200 default none" "$(reviewer_wait_budget_resolve pr-agent)"
max_wait_override=5
for _1789_p in $REVIEWER_LOOP_SUPPORTED_PLATFORMS; do
  run_test "1789_T1.2_override_wins_${_1789_p}" "5 override none" "$(reviewer_wait_budget_resolve "$_1789_p")"
done
unset max_wait_override

# --- T1.3: invalid configured values → default plus the D6 warning
_1789_invalid_n=0
for _1789_v in abc 0 -5 1.5 1e3 1000000 1234567 '""'; do
  _1789_invalid_n=$((_1789_invalid_n + 1))
  config_file="$(_1789_cfg "invalid_${_1789_invalid_n}" "review:
  wait_budgets:
    bugbot: ${_1789_v}")"
  _1789_raw="$_1789_v"
  [ "$_1789_v" = '""' ] && _1789_raw=""
  run_test "1789_T1.3_invalid_${_1789_invalid_n}_falls_back" "2400 default none" "$(reviewer_wait_budget_resolve bugbot 2>/dev/null)"
  run_test "1789_T1.3_invalid_${_1789_invalid_n}_warning" \
    "WARN: review.wait_budgets.bugbot value '${_1789_raw}' is not a positive whole number of seconds (1-999999); using the built-in default" \
    "$(reviewer_wait_budget_resolve bugbot 2>&1 >/dev/null)"
done
config_file="$(_1789_cfg empty_value 'review:
  wait_budgets:
    bugbot:
    pr-agent: 600')"
run_test "1789_T1.3_empty_value_falls_back" "2400 default none" "$(reviewer_wait_budget_resolve bugbot 2>/dev/null)"
run_contains "1789_T1.3_empty_value_warns" "review.wait_budgets.bugbot value '' is not a positive whole number of seconds (1-999999)" \
  "$(reviewer_wait_budget_resolve bugbot 2>&1 >/dev/null)"
run_test "1789_T1.3_missing_key_no_warning" "" "$(reviewer_wait_budget_resolve devin 2>&1 >/dev/null)"
config_file="$(_1789_cfg upper_bound 'review:
  wait_budgets:
    bugbot: 999999')"
run_test "1789_T1.3_upper_bound_configured" "999999 configured none" "$(reviewer_wait_budget_resolve bugbot)"
config_file="$(_1789_cfg unsupported 'review:
  wait_budgets:
    bugbot: 1800
    not-a-reviewer: 600')"
_1789_warn="$(reviewer_wait_budget_config_warnings 2>&1 >/dev/null)"
run_test "1789_T1.3_unsupported_key_warning" "WARN: review.wait_budgets.not-a-reviewer is not a supported platform; ignored" "$_1789_warn"
run_test "1789_T1.3_unsupported_key_does_not_disturb_valid" "1800 configured none" "$(reviewer_wait_budget_resolve bugbot)"
config_file="$(_1789_cfg flow 'review:
  wait_budgets: {bugbot: 1800}')"
_1789_warn="$(reviewer_wait_budget_config_warnings 2>&1 >/dev/null)"
run_test "1789_T1.3_flow_mapping_warning" "WARN: review.wait_budgets must be a block mapping; ignored" "$_1789_warn"
run_test "1789_T1.3_flow_mapping_uses_default" "2400 default none" "$(reviewer_wait_budget_resolve bugbot 2>/dev/null)"
config_file="$(_1789_cfg claude_cap 'review:
  wait_budgets:
    claude-code-action: 3601')"
run_test "1789_T1.3_claude_cap_falls_back" "1200 default none" "$(reviewer_wait_budget_resolve claude-code-action 2>/dev/null)"
run_test "1789_T1.3_claude_cap_warning" \
  "WARN: review.wait_budgets.claude-code-action value '3601' exceeds the companion's 3600-second maximum; using the built-in default" \
  "$(reviewer_wait_budget_resolve claude-code-action 2>&1 >/dev/null)"
config_file="$(_1789_cfg claude_at_cap 'review:
  wait_budgets:
    claude-code-action: 3600')"
run_test "1789_T1.3_claude_at_cap_configured" "3600 configured none" "$(reviewer_wait_budget_resolve claude-code-action)"
max_wait_override=7200
run_test "1789_T1.3_claude_override_not_adjusted" "7200 override none" "$(reviewer_wait_budget_resolve claude-code-action)"
unset max_wait_override
# CODEX_GITHUB_MAX_WAIT is codex-github's configured value and wins over YAML.
config_file="$(_1789_cfg codex 'review:
  wait_budgets:
    codex-github: 2100')"
run_test "1789_T1.3_codex_yaml_configured" "2100 configured none" "$(reviewer_wait_budget_resolve codex-github)"
CODEX_GITHUB_MAX_WAIT=2500
run_test "1789_T1.3_codex_env_over_yaml" "2500 configured none" "$(reviewer_wait_budget_resolve codex-github)"
CODEX_GITHUB_MAX_WAIT=nope
run_test "1789_T1.3_codex_invalid_env_falls_through_to_yaml" "2100 configured none" "$(reviewer_wait_budget_resolve codex-github 2>/dev/null)"
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
CODEX_GITHUB_MAX_WAIT=1000000
run_test "1789_T1.3_codex_oversized_env_falls_through_to_yaml" "2100 configured none" "$(reviewer_wait_budget_resolve codex-github 2>/dev/null)"
run_contains "1789_T1.3_codex_oversized_env_warns" "CODEX_GITHUB_MAX_WAIT value '1000000' is not a positive whole number of seconds (1-999999)" \
  "$(reviewer_wait_budget_resolve codex-github 2>&1 >/dev/null)"
unset CODEX_GITHUB_MAX_WAIT

# --- T1.4: implementation-plan/* — only Devin (plan D1) is shortened
config_file="$_1789_none_cfg"
branch_name="implementation-plan/x"
changed_files_count=500
run_test "1789_T1.4_devin_documentation_branch" "180 default documentation_branch" "$(reviewer_wait_budget_resolve devin)"
run_test "1789_T1.4_bugbot_keeps_default" "2400 default none" "$(reviewer_wait_budget_resolve bugbot)"
run_test "1789_T1.4_local_ai_reviewer_keeps_default" "1200 default none" "$(reviewer_wait_budget_resolve local-ai-reviewer)"
run_test "1789_T1.4_pr_agent_keeps_default" "1200 default none" "$(reviewer_wait_budget_resolve pr-agent)"
run_test "1789_T1.4_d1_set_is_devin_only" "devin" \
  "$(for _1789_p in $REVIEWER_LOOP_SUPPORTED_PLATFORMS; do reviewer_platform_reviews_documentation_branches "$_1789_p" || printf '%s' "$_1789_p"; done)"
changed_files_count=-1

# --- T1.5: spec/* with a configured Devin value — configured, never shortened
branch_name="spec/x"
config_file="$(_1789_cfg devin 'review:
  wait_budgets:
    devin: 900')"
run_test "1789_T1.5_spec_devin_configured" "900 configured none" "$(reviewer_wait_budget_resolve devin)"
max_wait_override=40
run_test "1789_T1.5_spec_devin_override" "40 override none" "$(reviewer_wait_budget_resolve devin)"
unset max_wait_override

# --- T1.6: PR_REVIEW_LOOP_DOC_MAX_WAIT keeps today's behavior, for Devin only
config_file="$_1789_none_cfg"
PR_REVIEW_LOOP_DOC_MAX_WAIT=240
export PR_REVIEW_LOOP_DOC_MAX_WAIT
run_test "1789_T1.6_doc_env_devin" "240 default documentation_branch" "$(reviewer_wait_budget_resolve devin)"
run_test "1789_T1.6_doc_env_not_applied_to_peer" "1200 default none" "$(reviewer_wait_budget_resolve pr-agent)"
PR_REVIEW_LOOP_DOC_MAX_WAIT=abc
run_test "1789_T1.6_doc_env_invalid_devin" "180 default documentation_branch" "$(reviewer_wait_budget_resolve devin 2>/dev/null)"
run_contains "1789_T1.6_doc_env_invalid_warns" "WARN: PR_REVIEW_LOOP_DOC_MAX_WAIT must be a positive integer; defaulting to 180" \
  "$(reviewer_wait_budget_resolve devin 2>&1 >/dev/null)"
run_test "1789_T1.6_doc_env_invalid_peer_silent" "" "$(reviewer_wait_budget_resolve bugbot 2>&1 >/dev/null)"
unset PR_REVIEW_LOOP_DOC_MAX_WAIT

# --- T1.7: large diff lengthens, never shortens, never touches an override
branch_name="feature/1789-x"
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
large_diff_threshold=50
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
large_diff_max_wait=2400
changed_files_count=80
config_file="$_1789_none_cfg"
run_test "1789_T1.7_large_diff_lengthens_default" "2400 default large_diff" "$(reviewer_wait_budget_resolve pr-agent)"
run_test "1789_T1.7_large_diff_leaves_bugbot" "2400 default none" "$(reviewer_wait_budget_resolve bugbot)"
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
max_wait_override=30
run_test "1789_T1.7_large_diff_leaves_override" "30 override none" "$(reviewer_wait_budget_resolve pr-agent)"
unset max_wait_override
config_file="$(_1789_cfg large 'review:
  wait_budgets:
    bugbot: 3000
    local-ai-reviewer: 1500')"
run_test "1789_T1.7_large_diff_never_shortens" "3000 configured none" "$(reviewer_wait_budget_resolve bugbot)"
run_test "1789_T1.7_large_diff_lengthens_configured" "2400 configured large_diff" "$(reviewer_wait_budget_resolve local-ai-reviewer)"
changed_files_count=50
run_test "1789_T1.7_at_threshold_not_extended" "1500 configured none" "$(reviewer_wait_budget_resolve local-ai-reviewer)"
changed_files_count=-1
run_test "1789_T1.7_fetch_failed_not_extended" "1500 configured none" "$(reviewer_wait_budget_resolve local-ai-reviewer)"
changed_files_count=80
branch_name="spec/x"
config_file="$_1789_none_cfg"
run_test "1789_T1.7_doc_branch_not_extended" "1200 default none" "$(reviewer_wait_budget_resolve pr-agent)"
branch_name="feature/1789-x"
changed_files_count=-1
unset large_diff_threshold large_diff_max_wait

# --- Per-run cache and PLATFORM_WAIT_BUDGETS value
branch_name="implementation-plan/x"
config_file="$(_1789_cfg summary 'review:
  wait_budgets:
    pr-agent: 600')"
reviewer_wait_budget_cache_platforms=()
reviewer_wait_budget_cache_values=()
reviewer_wait_budget_cache_fill bugbot pr-agent devin bugbot
run_test "1789_cache_dedupes_platforms" "3" "${#reviewer_wait_budget_cache_platforms[@]}"
run_test "1789_platform_wait_budgets_value" \
  "bugbot:2400:default,pr-agent:600:configured,devin:180:default:documentation_branch" \
  "$(reviewer_wait_budgets_summary bugbot pr-agent devin)"
run_test "1789_cache_lookup_hit" "600 configured none" "$(reviewer_wait_budget_for_platform pr-agent)"
run_test "1789_cache_lookup_miss_resolves" "1200 default none" "$(reviewer_wait_budget_for_platform local-ai-reviewer)"
reviewer_wait_budget_cache_platforms=()
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
reviewer_wait_budget_cache_values=()
branch_name="feature/1789-x"

# Dispatch sites use the per-platform budget and poll interval, including the
# second local pass (plan D4: local-ai-reviewer keeps its own budget).
_1789_loop_src="$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
run_test "1789_main_dispatch_uses_platform_budget" "1" \
  "$(grep -c 'run_platform_review "\$platform_name" "\$pr_number" "\$branch_name" "\$platform_poll_interval" "\$platform_max_wait"' "$_1789_loop_src")"
run_test "1789_second_pass_uses_local_budget" "1" \
  "$(grep -c 'run_platform_review "local-ai-reviewer" "\$pr_number_arg" "\$branch_name" "\$_sl_poll_interval" "\$_sl_max_wait"' "$_1789_loop_src")"
run_test "1789_platform_wait_budgets_printed" "1" \
  "$(grep -c 'print_kv PLATFORM_WAIT_BUDGETS' "$_1789_loop_src")"
run_test "1789_no_global_max_wait_dispatch" "0" \
  "$(grep -c '"\$poll_interval" "\$max_wait")' "$_1789_loop_src" || true)"

# --- T1.8: invalid --max-wait refused before any gh call (plan D13)
_1789_n=0
for _1789_v in 0 abc -5 1.5 1000000; do
  _1789_n=$((_1789_n + 1))
  _1789_log="$_1789_dir/gh-${_1789_n}.log"
  : > "$_1789_log"
  set +e
  _1789_err="$(MOCK_GH_CALL_LOG="$_1789_log" HARNESS_MODE=0 \
    bash "$_1789_loop_src" 917890 --repo acme/widgets --branch feature/1789-x --max-wait "$_1789_v" 2>&1 >/dev/null)"
  _1789_rc=$?
  set -e
  run_test "1789_T1.8_max_wait_${_1789_n}_exit_64" "64" "$_1789_rc"
  run_contains "1789_T1.8_max_wait_${_1789_n}_message" \
    "--max-wait must be a positive whole number of seconds (1-999999) (got '${_1789_v}')." "$_1789_err"
  run_contains "1789_T1.8_max_wait_${_1789_n}_usage" "Usage: ./scripts/development-workflow/pr-review-loop.sh" "$_1789_err"
  run_test "1789_T1.8_max_wait_${_1789_n}_no_gh_call" "0" "$(grep -c . "$_1789_log" || true)"
done
run_test "1789_T1.8_valid_bounds" "yes yes no" \
  "$(for _1789_v in 1 999999 1000000; do if reviewer_wait_seconds_is_valid "$_1789_v"; then printf 'yes '; else printf 'no '; fi; done | sed 's/ $//')"

# --- T1.9: poll interval resolver (plan D14)
branch_name="feature/1789-x"
run_test "1789_T1.9_default_120" "120" "$(reviewer_poll_interval_resolve pr-agent 1200)"
run_test "1789_T1.9_codex_default_60" "60" "$(reviewer_poll_interval_resolve codex-github 1800)"
CODEX_GITHUB_POLL_INTERVAL=90
export CODEX_GITHUB_POLL_INTERVAL
run_test "1789_T1.9_codex_env_interval" "90" "$(reviewer_poll_interval_resolve codex-github 1800)"
run_test "1789_T1.9_codex_env_not_applied_to_peer" "120" "$(reviewer_poll_interval_resolve bugbot 2400)"
unset CODEX_GITHUB_POLL_INTERVAL
branch_name="spec/x"
run_test "1789_T1.9_documentation_30" "30" "$(reviewer_poll_interval_resolve local-ai-reviewer 1200)"
run_test "1789_T1.9_documentation_codex_keeps_60" "60" "$(reviewer_poll_interval_resolve codex-github 1800)"
branch_name="feature/1789-x"
poll_interval_override=7
run_test "1789_T1.9_explicit_wins" "7" "$(reviewer_poll_interval_resolve codex-github 1800)"
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
poll_interval_override=5000
run_test "1789_T1.9_explicit_clamped_below_budget" "600" "$(reviewer_poll_interval_resolve pr-agent 1200)"
unset poll_interval_override
run_test "1789_T1.9_clamp_default" "50" "$(reviewer_poll_interval_resolve pr-agent 100)"
run_test "1789_T1.9_clamp_budget_2" "1" "$(reviewer_poll_interval_resolve pr-agent 2)"
run_test "1789_T1.9_clamp_budget_1" "1" "$(reviewer_poll_interval_resolve pr-agent 1)"

# --- T1.10: config reader edge cases (parser-risk addendum E1–E13)
_1789_read() { workflow_config_review_wait_budget "$1" "$2"; }
run_test "1789_T1.10_E1_plain" "1800" "$(_1789_read bugbot "$(_1789_cfg e1 'review:
  wait_budgets:
    bugbot: 1800')")"
run_test "1789_T1.10_E2_double_quoted" "1800" "$(_1789_read bugbot "$(_1789_cfg e2a 'review:
  wait_budgets:
    bugbot: "1800"')")"
run_test "1789_T1.10_E2_single_quoted" "1800" "$(_1789_read bugbot "$(_1789_cfg e2b "review:
  wait_budgets:
    bugbot: '1800'")")"
run_test "1789_T1.10_E3_trailing_comment" "1800" "$(_1789_read bugbot "$(_1789_cfg e3 'review:
  wait_budgets:
    bugbot: 1800  # slow vendor')")"
_1789_e4="$(_1789_cfg e4 'review:
  wait_budgets:
    local-ai-reviewer: 1500')"
run_test "1789_T1.10_E4_hyphenated_key" "1500" "$(_1789_read local-ai-reviewer "$_1789_e4")"
run_test "1789_T1.10_E5_prefix_lookalike" "" "$(_1789_read local-ai "$_1789_e4")"
run_test "1789_T1.10_E6_under_on_ready" "" "$(_1789_read bugbot "$(_1789_cfg e6a 'review:
  on_ready:
    github: [local-ai-reviewer]
    bugbot: 1800')")"
run_test "1789_T1.10_E6_top_level_wait_budgets" "" "$(_1789_read bugbot "$(_1789_cfg e6b 'review:
  max_cycles: 10
wait_budgets:
  bugbot: 1800')")"
run_test "1789_T1.10_E6_wait_budgets_under_on_ready" "" "$(_1789_read bugbot "$(_1789_cfg e6c 'review:
  on_ready:
    wait_budgets:
      bugbot: 1800')")"
run_test "1789_T1.10_E7_scope_end" "" "$(_1789_read bugbot "$(_1789_cfg e7 'review:
  wait_budgets:
  max_cycles: 10
    bugbot: 1800')")"
run_test "1789_T1.10_E8_commented_key" "" "$(_1789_read bugbot "$(_1789_cfg e8 'review:
  wait_budgets:
    # bugbot: 1800
    pr-agent: 600')")"
run_test "1789_T1.10_E9_missing_file" "" "$(_1789_read bugbot "$_1789_dir/absent.yaml")"
run_test "1789_T1.10_E9_missing_section" "" "$(_1789_read bugbot "$(_1789_cfg e9b 'issue_tracker:
  provider: github_projects')")"
run_test "1789_T1.10_E9_missing_key" "" "$(_1789_read bugbot "$(_1789_cfg e9c 'review:
  wait_budgets:
    pr-agent: 600')")"
run_test "1789_T1.10_E10_duplicate_key_first_wins" "1800" "$(_1789_read bugbot "$(_1789_cfg e10 'review:
  wait_budgets:
    bugbot: 1800
    bugbot: 900')")"
run_test "1789_T1.10_E11_flow_mapping" "__flow__" "$(_1789_read bugbot "$(_1789_cfg e11 'review:
  wait_budgets: {bugbot: 1800}')")"
run_test "1789_T1.10_E12_deeper_indentation" "1800" "$(_1789_read bugbot "$(_1789_cfg e12 'review:
    max_cycles: 10
    wait_budgets:
        pr-agent: 600
        bugbot: 1800')")"
_1789_n=0
for _1789_v in abc 0 -5 1.5 1e3 1234567; do
  _1789_n=$((_1789_n + 1))
  run_test "1789_T1.10_E13_raw_value_${_1789_n}" "$_1789_v" "$(_1789_read bugbot "$(_1789_cfg "e13_${_1789_n}" "review:
  wait_budgets:
    bugbot: ${_1789_v}")")"
done
_1789_e13_empty="$(_1789_cfg e13_empty 'review:
  wait_budgets:
    bugbot:')"
run_test "1789_T1.10_E13_empty_value" "" "$(_1789_read bugbot "$_1789_e13_empty")"
run_test "1789_T1.10_E13_empty_value_key_listed" "bugbot" "$(workflow_config_review_wait_budget_keys "$_1789_e13_empty")"
run_test "1789_T1.10_keys_in_file_order_unique" "bugbot,pr-agent,bogus" \
  "$(workflow_config_review_wait_budget_keys "$(_1789_cfg keys 'review:
  wait_budgets:
    bugbot: 1
    pr-agent: 2
    bugbot: 3
    bogus: 4')" | paste -sd, -)"

# ---------------------------------------------------------------------------
# Phase 2a — outcome helpers (plan D8), the label function (D9), the companion
# watchdog/exit-4 contracts as seen by the loop handlers (D4, D8 Claude and
# Haystack rows), the CodeRabbit CLI kept skip, and the Rule 5 consumers of
# no_verdict_yet. Tests: T2.1 (local-ai-reviewer, claude-code-action,
# haystack rows), T2.4 (CodeRabbit CLI kept skip), T2.6 (availability class),
# T2.8 (loop mapping), T2.10, T2.27 (loop arm), T2.28.
# ---------------------------------------------------------------------------

# --- D8 helper definitions sit before the harness return point
_1789_ret_line="$(grep -n '^\[ "\$_HARNESS_MODE_EFFECTIVE" -eq 1 \] && return 0' "$_1789_loop_src" | head -n 1 | cut -d: -f1)"
_1789_helpers_ok="yes"
for _1789_fn in print_no_verdict_yet print_no_verdict_yet_kept_skip_keys reviewer_loop_platform_outcome_class reviewer_loop_reason_in_list reviewer_loop_build_failed_completion_jq; do
  _1789_fn_line="$(grep -n "^${_1789_fn}() {" "$_1789_loop_src" | head -n 1 | cut -d: -f1)"
  if [ -z "$_1789_fn_line" ] || [ -z "$_1789_ret_line" ] || [ "$_1789_fn_line" -ge "$_1789_ret_line" ]; then
    _1789_helpers_ok="no:${_1789_fn}"
  fi
done
run_test "1789_T2_helpers_before_harness_return" "yes" "$_1789_helpers_ok"

# --- print_no_verdict_yet block (D8)
run_test "1789_T2_print_no_verdict_yet_block" \
  "RESULT=waiting_on_reviewer|REASON=reviewer-no-verdict-yet|NO_VERDICT_YET=1|WAIT_EXPIRED_DETAIL=check_not_completed|PENDING_REVIEWER=bugbot|PENDING_REVIEW_HEAD_SHA=abc123|REVIEW_REQUESTED_AT=2026-09-23T12:35:16Z|COMMENT_COUNT=0|BLOCKING_COUNT=0|SUGGESTION_COUNT=0" \
  "$(print_no_verdict_yet bugbot check_not_completed abc123 2026-09-23T12:35:16Z | paste -sd'|' -)"
run_test "1789_T2_print_no_verdict_yet_omits_unknown_requested_at" "0" \
  "$(print_no_verdict_yet bugbot check_not_completed abc123 "" | grep -c '^REVIEW_REQUESTED_AT=' || true)"
run_test "1789_T2_kept_skip_keys" "NO_VERDICT_YET=1|DISPLAY_RESULT=no verdict yet (non-blocking skip: timeout)" \
  "$(print_no_verdict_yet_kept_skip_keys timeout | paste -sd'|' -)"

# --- reviewer_loop_platform_outcome_class (D8 table, T2.6 availability rows)
for _1789_case in \
    "clean||0|verdict_received" \
    "needs_fixes|blocking|0|verdict_received" \
    "needs_rerun|stale_verdict|0|verdict_received" \
    "waiting_on_reviewer|reviewer-no-verdict-yet|1|no_verdict_yet" \
    "waiting_on_reviewer|codex-github-review-pending|0|no_verdict_yet" \
    "skipped|timeout|1|no_verdict_yet" \
    "skipped|no_review|1|no_verdict_yet" \
    "skipped|no_output|0|skipped_failure_evidence" \
    "skipped|unavailable|0|skipped_failure_evidence" \
    "skipped|cli_failed|0|skipped_failure_evidence" \
    "skipped|explicit-skip|0|skipped" \
    "skipped|timeout|0|skipped" \
    "escalate|rate_limited|0|existing_handling" \
    "escalate|rate_limit_max_retries|0|existing_handling" \
    "escalate|codex-github-usage-limit|0|existing_handling" \
    "escalate|codex-github-account-not-connected|0|existing_handling" \
    "escalate|bugbot-usage-limit|0|existing_handling" \
    "escalate|quota_exhausted|0|existing_handling" \
    "escalate|claude_code_action_run_failed|0|reviewer_failed" \
    "escalate|timeout|0|reviewer_failed" \
    "bogus|whatever|0|reviewer_failed"; do
  IFS='|' read -r _1789_r _1789_reason _1789_flag _1789_expected <<<"$_1789_case"
  run_test "1789_T2_class_${_1789_r}_${_1789_reason:-none}_${_1789_flag}" "$_1789_expected" \
    "$(reviewer_loop_platform_outcome_class "$_1789_r" "$_1789_reason" "$_1789_flag")"
done

# --- reason lists (D8)
run_test "1789_T2_no_verdict_reasons" "reviewer-no-verdict-yet codex-github-review-pending codex-github-reaction-without-review" \
  "${REVIEWER_LOOP_NO_VERDICT_REASONS[*]}"
run_test "1789_T2_failure_skip_reasons" "unavailable thread-check-failed forbidden unauthorized no_output invalid_json ambiguous_output cli_failed" \
  "${REVIEWER_LOOP_FAILURE_SKIP_REASONS[*]}"
run_test "1789_T2_failure_skip_reasons_exclude_expired_waits" "no" \
  "$(if reviewer_loop_reason_in_list timeout "${REVIEWER_LOOP_FAILURE_SKIP_REASONS[@]}" \
      || reviewer_loop_reason_in_list pending_timeout "${REVIEWER_LOOP_FAILURE_SKIP_REASONS[@]}"; then echo yes; else echo no; fi)"
run_test "1789_T2_failed_check_conclusions" "failure timed_out cancelled action_required startup_failure stale" \
  "${REVIEWER_LOOP_FAILED_CHECK_CONCLUSIONS[*]}"
run_test "1789_T2_reason_in_list_empty_needle" "no" \
  "$(reviewer_loop_reason_in_list "" "" a && echo yes || echo no)"

# --- REVIEWER_FAILED_COMPLETION_JQ predicate (D8 failure-type completion signals)
_1789_fc() { jq -nc "$REVIEWER_FAILED_COMPLETION_JQ"' '"$1"' | reviewer_failed_completion'; }
run_test "1789_T2_fc_check_timed_out" "true" "$(_1789_fc '{status:"completed",conclusion:"timed_out"}')"
run_test "1789_T2_fc_check_cancelled" "true" "$(_1789_fc '{status:"completed",conclusion:"cancelled"}')"
run_test "1789_T2_fc_check_stale" "true" "$(_1789_fc '{status:"completed",conclusion:"stale"}')"
run_test "1789_T2_fc_check_success" "false" "$(_1789_fc '{status:"completed",conclusion:"success"}')"
run_test "1789_T2_fc_check_neutral" "false" "$(_1789_fc '{status:"completed",conclusion:"neutral"}')"
run_test "1789_T2_fc_check_in_progress" "false" "$(_1789_fc '{status:"in_progress",conclusion:null}')"
run_test "1789_T2_fc_graphql_check_uppercase" "true" "$(_1789_fc '{__typename:"CheckRun",status:"COMPLETED",conclusion:"STARTUP_FAILURE"}')"
run_test "1789_T2_fc_status_failure" "true" "$(_1789_fc '{context:"Devin",state:"failure"}')"
run_test "1789_T2_fc_status_error" "true" "$(_1789_fc '{context:"Devin",state:"error"}')"
run_test "1789_T2_fc_graphql_status_uppercase" "true" "$(_1789_fc '{__typename:"StatusContext",context:"Devin",state:"ERROR"}')"
run_test "1789_T2_fc_status_success" "false" "$(_1789_fc '{context:"Devin",state:"success"}')"
run_test "1789_T2_fc_status_pending" "false" "$(_1789_fc '{context:"Devin",state:"pending"}')"
run_test "1789_T2_fc_non_object" "false" "$(_1789_fc 'null')"
run_test "1789_T2_fc_newest_per_key_governs" "false" \
  "$(jq -nc "$STATUS_CHECK_ROLLUP_DEDUPE_JQ$REVIEWER_FAILED_COMPLETION_JQ"'[
      {name:"Devin Review",id:1,started_at:"2026-01-01T00:00:00Z",status:"completed",conclusion:"timed_out"},
      {name:"Devin Review",id:2,started_at:"2026-01-01T00:05:00Z",status:"completed",conclusion:"success"}
    ] | dedupe_status_check_rollup | last | reviewer_failed_completion')"
run_test "1789_T2_fc_newest_failed_governs" "true" \
  "$(jq -nc "$STATUS_CHECK_ROLLUP_DEDUPE_JQ$REVIEWER_FAILED_COMPLETION_JQ"'[
      {name:"Devin Review",id:1,started_at:"2026-01-01T00:00:00Z",status:"completed",conclusion:"success"},
      {name:"Devin Review",id:2,started_at:"2026-01-01T00:05:00Z",status:"completed",conclusion:"cancelled"}
    ] | dedupe_status_check_rollup | last | reviewer_failed_completion')"

# --- D9 label function (T2.28 label-function rows)
_1789_label() { if reviewer_failed_label_required_for_result "$1" "${2:-}"; then echo yes; else echo no; fi; }
for _1789_reason in no_output invalid_json ambiguous_output cli_failed unavailable thread-check-failed forbidden unauthorized; do
  run_test "1789_T2.28_label_skipped_${_1789_reason}_required" "yes" "$(_1789_label skipped "$_1789_reason")"
done
for _1789_reason in timeout pending_timeout rate_limited analysis_skipped_file_limit explicit-skip disabled_by_config no_review no_check_run not_configured; do
  run_test "1789_T2.28_label_skipped_${_1789_reason}_not_required" "no" "$(_1789_label skipped "$_1789_reason")"
done
run_test "1789_T2_label_waiting_not_required" "no" "$(_1789_label waiting_on_reviewer reviewer-no-verdict-yet)"
run_test "1789_T2_label_escalate_claude_run_failed" "yes" "$(_1789_label escalate claude_code_action_run_failed)"
run_test "1789_T2.6_label_escalate_rate_limited_unchanged" "no" "$(_1789_label escalate rate_limited)"
run_test "1789_T2.6_label_escalate_quota_exhausted_unchanged" "yes" "$(_1789_label escalate quota_exhausted)"

# --- Rule 5 consumers of no_verdict_yet (T2.10)
run_test "1789_T2.10_normalize_waiting" "no_verdict_yet" \
  "$(reviewer_loop_normalize_platform_outcome waiting_on_reviewer reviewer-no-verdict-yet)"
run_test "1789_T2.10_normalize_codex_wait_reason" "no_verdict_yet" \
  "$(reviewer_loop_normalize_platform_outcome waiting_on_reviewer codex-github-review-pending)"
run_test "1789_T2.10_normalize_kept_skip_flag" "no_verdict_yet" \
  "$(reviewer_loop_normalize_platform_outcome skipped timeout 1)"
run_test "1789_T2.10_normalize_skip_without_flag" "skipped" \
  "$(reviewer_loop_normalize_platform_outcome skipped timeout)"
run_test "1789_T2.10_normalize_unavailable_unchanged" "unavailable" \
  "$(reviewer_loop_normalize_platform_outcome skipped unavailable 0)"
run_test "1789_T2.10_record_json_forwards_flag" "no_verdict_yet|skipped|no_review" \
  "$(reviewer_loop_platform_result_record_json pr-agent skipped no_review 1 | jq -r '[.result,.raw_result,.raw_reason] | join("|")')"
run_test "1789_T2.10_record_json_default_flag" "skipped" \
  "$(reviewer_loop_platform_result_record_json pr-agent skipped no_review | jq -r '.result')"
_1789_nvy_head="1789dddddddddddddddddddddddddddddddddddd"
_1789_nvy_payload="$(jq -nc --arg head "$_1789_nvy_head" '{
  schema: "reviewer_loop_history.v1",
  entries: [{
    iteration: 1,
    platform_results: [{platform: "local-ai-reviewer", result: "no_verdict_yet", raw_result: "waiting_on_reviewer", raw_reason: "reviewer-no-verdict-yet"}],
    reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $head, classification: "current"}]
  }]
}')"
run_test "1789_T2.10_local_pass_required_no_evidence" "no_evidence" \
  "$(reviewer_loop_local_pass_required "$_1789_nvy_payload" "$_1789_nvy_head" "local-ai-reviewer")"
run_test "1789_T2.10_local_evidence_state" "no_verdict_yet" \
  "$(reviewer_loop_local_evidence_state '{"outcome":"no_verdict_yet","head_sha":""}' "$_1789_nvy_head")"
run_test "1789_T2.10_local_evidence_state_label" "No verdict yet" \
  "$(reviewer_loop_local_evidence_state_label no_verdict_yet)"
run_test "1789_T2.10_local_evidence_not_a_miss" "not_a_miss" \
  "$(reviewer_loop_missed_finding_classification no_verdict_yet)"

# --- Loop handler composition helpers
_1789_reset_processing_globals() {
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  total_comment_count=0
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  total_blocking_count=0
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  total_suggestion_count=0
  reviewer_failed_required=0
  compare_mode=0
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  compare_verdicts=()
  compare_first_blocking_result=""
  compare_first_blocking_reason=""
  compare_first_blocking_output=""
  compare_first_blocking_status=0
  reviewer_loop_gate_break_result=""
  platform_peer_evidence=()
  platform_result_records=()
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  platform_reviewed_heads=()
  platform_result_tokens=()
  platform_blocking_outputs=()
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  platform_timing_records=()
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  reviewer_loop_timing_pending=0
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  aggregate_blocking_paths=()
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  aggregate_blocking_findings=()
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  platform_policy_status_notes=()
  aggregate_result="skipped"
  aggregate_reason=""
  aggregate_output=""
  aggregate_status=0
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  aggregate_advisory_labels=""
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  phase_after_clean_enabled=0
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  phase_after_clean_started=0
  reviewer_loop_platform_loop_should_break=0
  loop_head_sha="1789aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  last_platform=""
}
_1789_handler_overrides='
  require_gh() { :; }
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  reviewer_for_branch() { printf "developer\n"; }
  check_unresolved_threads() { printf "0\n"; }
'
# _1789_stub_companion <script-name> <stdout> <exit>: a stub companion under a
# fake workflow root (the Area 1710 pattern).
_1789_stub_root="$_1789_dir/stub-root"
mkdir -p "$_1789_stub_root/scripts/development-workflow"
_1789_stub_companion() {
  printf '#!/usr/bin/env bash\nprintf %%s %q\nexit %s\n' "$2" "$3" \
    > "$_1789_stub_root/scripts/development-workflow/$1"
  chmod +x "$_1789_stub_root/scripts/development-workflow/$1"
}
# _1789_run_handler <handler> <max_wait>: runs a loop handler against the stub
# root and prints its output followed by EXIT=<return status>.
_1789_run_handler() {
  (
    eval "$_1789_handler_overrides"
    workflow_repo_root() { printf '%s\n' "$_1789_stub_root"; }
    repo_root="$_1789_stub_root"
    loop_head_sha="${_1789_handler_loop_head-1789aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
    export MOCK_GH_OUTPUT="false"
    _ec=0
    "$1" "42" "feature/1789-x" "1" "${2:-30}" 2>/dev/null || _ec=$?
    printf 'EXIT=%s\n' "$_ec"
  )
}

# --- T2.1 local-ai-reviewer: companion exit 4 → No verdict yet stopped_at_budget
_1789_stub_companion local-ai-reviewer.sh "$(printf 'REVIEWED_HEAD=1789bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\nRESULT=waiting_on_reviewer\nREASON=reviewer-no-verdict-yet\nNO_VERDICT_YET=1\nWAIT_EXPIRED_DETAIL=stopped_at_budget\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')" 4
_1789_out="$(_1789_run_handler run_local_ai_reviewer_review 30)"
run_test "1789_T2.1_local_ai_result" "waiting_on_reviewer" "$(kv_value_default RESULT "$_1789_out" "")"
run_test "1789_T2.1_local_ai_reason" "reviewer-no-verdict-yet" "$(kv_value_default REASON "$_1789_out" "")"
run_test "1789_T2.1_local_ai_flag" "1" "$(kv_value_default NO_VERDICT_YET "$_1789_out" "")"
run_test "1789_T2.1_local_ai_detail" "stopped_at_budget" "$(kv_value_default WAIT_EXPIRED_DETAIL "$_1789_out" "")"
run_test "1789_T2.1_local_ai_pending_reviewer" "local-ai-reviewer" "$(kv_value_default PENDING_REVIEWER "$_1789_out" "")"
run_test "1789_T2.1_local_ai_pending_head" "1789bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" "$(kv_value_default PENDING_REVIEW_HEAD_SHA "$_1789_out" "")"
run_test "1789_T2.1_local_ai_exit" "4" "$(kv_value_default EXIT "$_1789_out" "")"
_1789_reset_processing_globals
reviewer_loop_process_platform_output "local-ai-reviewer" 1 "$_1789_out" 4 1 >/dev/null 2>&1
run_test "1789_T2.1_local_ai_aggregate_waiting" "waiting_on_reviewer" "$aggregate_result"
run_test "1789_T2.1_local_ai_aggregate_reason" "reviewer-no-verdict-yet" "$aggregate_reason"
run_test "1789_T2.1_local_ai_breaks" "1" "$reviewer_loop_platform_loop_should_break"
run_test "1789_T2.1_local_ai_label_not_required" "0" "$reviewer_failed_required"
run_test "1789_T2.10_local_ai_record_no_verdict_yet" "no_verdict_yet" \
  "$(printf '%s\n' "${platform_result_records[@]}" | jq -sr 'last | .result')"

# Exit 2 from the companion (a real failure) still escalates.
_1789_stub_companion local-ai-reviewer.sh "$(printf 'RESULT=escalate\nREASON=malformed_output\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')" 2
_1789_out="$(_1789_run_handler run_local_ai_reviewer_review 30)"
run_test "1789_T2.3_local_ai_failure_escalates" "escalate|malformed_output|2" \
  "$(kv_value_default RESULT "$_1789_out" "")|$(kv_value_default REASON "$_1789_out" "")|$(kv_value_default EXIT "$_1789_out" "")"

# --- T2.1/T2.8 claude-code-action: companion exit 4 → run_not_completed; exit 2 → run failed
_1789_stub_companion claude-code-action-reviewer.sh 'VERDICT: NO_VERDICT_YET' 4
_1789_out="$(_1789_run_handler run_claude_code_action_review 30)"
run_test "1789_T2.8_claude_exit4_result" "waiting_on_reviewer" "$(kv_value_default RESULT "$_1789_out" "")"
run_test "1789_T2.8_claude_exit4_reason" "reviewer-no-verdict-yet" "$(kv_value_default REASON "$_1789_out" "")"
run_test "1789_T2.8_claude_exit4_detail" "run_not_completed" "$(kv_value_default WAIT_EXPIRED_DETAIL "$_1789_out" "")"
run_test "1789_T2.8_claude_exit4_pending_reviewer" "claude-code-action" "$(kv_value_default PENDING_REVIEWER "$_1789_out" "")"
run_test "1789_T2.8_claude_exit4_pending_head" "1789aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$(kv_value_default PENDING_REVIEW_HEAD_SHA "$_1789_out" "")"
run_test "1789_T2.8_claude_exit4_return" "4" "$(kv_value_default EXIT "$_1789_out" "")"
_1789_stub_companion claude-code-action-reviewer.sh 'VERDICT: FAILED' 2
_1789_out="$(_1789_run_handler run_claude_code_action_review 30)"
run_test "1789_T2.8_claude_exit2_result" "escalate" "$(kv_value_default RESULT "$_1789_out" "")"
run_test "1789_T2.8_claude_exit2_reason" "claude_code_action_run_failed" "$(kv_value_default REASON "$_1789_out" "")"
run_test "1789_T2.8_claude_exit2_return" "2" "$(kv_value_default EXIT "$_1789_out" "")"
run_test "1789_T2.8_claude_exit2_label_required" "yes" "$(_1789_label escalate claude_code_action_run_failed)"
_1789_stub_companion claude-code-action-reviewer.sh 'VERDICT: UNAVAILABLE' 3
_1789_out="$(_1789_run_handler run_claude_code_action_review 30)"
run_test "1789_T2.8_claude_exit3_unavailable" "escalate|unavailable" \
  "$(kv_value_default RESULT "$_1789_out" "")|$(kv_value_default REASON "$_1789_out" "")"

# --- T2.27 haystack exit-2 arm
for _1789_case in \
    "timeout|0|waiting_on_reviewer|timeout|4" \
    "pending_timeout|0|waiting_on_reviewer|pending_timeout|4" \
    "pending_check_run|1|waiting_on_reviewer|pending_check_run|4" \
    "pending_check_run|0|escalate||2" \
    "check_run_timed_out|0|escalate||2" \
    "check_run_cancelled|0|escalate||2" \
    "check_run_stale|0|escalate||2" \
    "check_run_unknown|0|escalate||2"; do
  IFS='|' read -r _1789_reason _1789_flag _1789_expected_result _1789_expected_detail _1789_expected_exit <<<"$_1789_case"
  _1789_body="RESULT=skipped
REVIEWED_HEAD=1789cccccccccccccccccccccccccccccccccccc
REASON=${_1789_reason}
BLOCKING_COUNT=0
SUGGESTION_COUNT=0
COMMENT_COUNT=0"
  [ "$_1789_flag" = "1" ] && _1789_body="${_1789_body}
HAYSTACK_BUDGET_EXPIRED=1"
  _1789_stub_companion haystack-reviewer.sh "${_1789_body}
" 2
  _1789_out="$(_1789_run_handler run_haystack_review 30)"
  _1789_tag="${_1789_reason}_key${_1789_flag}"
  run_test "1789_T2.27_haystack_${_1789_tag}_result" "$_1789_expected_result" "$(kv_value_default RESULT "$_1789_out" "")"
  run_test "1789_T2.27_haystack_${_1789_tag}_exit" "$_1789_expected_exit" "$(kv_value_default EXIT "$_1789_out" "")"
  if [ "$_1789_expected_result" = "waiting_on_reviewer" ]; then
    run_test "1789_T2.27_haystack_${_1789_tag}_reason" "reviewer-no-verdict-yet" "$(kv_value_default REASON "$_1789_out" "")"
    run_test "1789_T2.27_haystack_${_1789_tag}_detail" "$_1789_expected_detail" "$(kv_value_default WAIT_EXPIRED_DETAIL "$_1789_out" "")"
    run_test "1789_T2.27_haystack_${_1789_tag}_pending_head" "1789cccccccccccccccccccccccccccccccccccc" \
      "$(kv_value_default PENDING_REVIEW_HEAD_SHA "$_1789_out" "")"
    run_test "1789_T2.27_haystack_${_1789_tag}_label" "no" "$(_1789_label waiting_on_reviewer reviewer-no-verdict-yet)"
  else
    run_test "1789_T2.27_haystack_${_1789_tag}_reason" "$_1789_reason" "$(kv_value_default REASON "$_1789_out" "")"
    run_test "1789_T2.27_haystack_${_1789_tag}_label" "yes" "$(_1789_label escalate "$_1789_reason")"
  fi
done
_1789_stub_companion haystack-reviewer.sh "$(printf 'RESULT=skipped\nBLOCKING_COUNT=0\n')" 2
_1789_out="$(_1789_run_handler run_haystack_review 30)"
run_test "1789_T2.27_haystack_missing_reason_fails_closed" "escalate|2" \
  "$(kv_value_default RESULT "$_1789_out" "")|$(kv_value_default EXIT "$_1789_out" "")"

# --- T2.28 / T2.4 CodeRabbit CLI composed from the real companion through the
# loop handler: an immediate CLI exit 124 with empty stdout is no_output
# (failure evidence, label required, non-blocking); a CLI that sleeps past the
# budget is the kept `timeout` skip reported as No verdict yet.
_1789_cr_repo="$_1789_dir/cr-repo"
_1789_cr_bin="$_1789_dir/cr-bin"
mkdir -p "$_1789_cr_repo" "$_1789_cr_bin"
# The harness PATH carries a strict git mock; the fixture and the real
# companion need the genuine git.
_1789_real_git() { PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -C "$_1789_cr_repo" "$@"; }
_1789_real_git init -q
_1789_real_git config user.email "test@example.com"
_1789_real_git config user.name "Test User"
printf 'fixture\n' > "$_1789_cr_repo/README.md"
_1789_real_git add README.md
_1789_real_git commit -q -m fixture
_1789_real_git remote add origin "git@github.com:owner/repo.git"
_1789_cr_head="$(_1789_real_git rev-parse HEAD)"
cat > "$_1789_cr_bin/gh" <<MOCK_GH
#!/usr/bin/env bash
case "\$*" in
  *"pr view 42"*"--json baseRefName,headRefName,headRefOid"*)
    printf '{"baseRefName":"develop","headRefName":"feature/1789-x","headRefOid":"%s"}\n' "$_1789_cr_head"
    exit 0
    ;;
esac
exit 1
MOCK_GH
cat > "$_1789_cr_bin/cr" <<'MOCK_CR'
#!/usr/bin/env bash
if [ -n "${MOCK_1789_CR_SLEEP:-}" ]; then
  sleep "$MOCK_1789_CR_SLEEP"
fi
exit "${MOCK_1789_CR_EXIT:-0}"
MOCK_CR
chmod +x "$_1789_cr_bin/gh" "$_1789_cr_bin/cr"
_1789_run_cr_cli() {
  (
    eval "$_1789_handler_overrides"
    workflow_repo_root() { printf '%s\n' "$REPO_ROOT"; }
    # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
    repo_root="$_1789_cr_repo"
    unset AI_DEV_WORKFLOW_CONFIG_FILE
    config_file=""
    PATH="$_1789_cr_bin:$TEST_PR_REVIEW_LOOP_REAL_PATH"
    export CODERABBIT_CLI_RATE_LIMIT_POLICY=warn
    export MOCK_1789_CR_EXIT="${1:-0}" MOCK_1789_CR_SLEEP="${2:-}"
    _ec=0
    run_coderabbit_cli_review "42" "feature/1789-x" "1" "${3:-30}" 2>/dev/null || _ec=$?
    printf 'EXIT=%s\n' "$_ec"
  )
}

_1789_cr_out="$(_1789_run_cr_cli 124 "" 30)"
run_test "1789_T2.28_cli_exit124_result" "skipped" "$(kv_value_default RESULT "$_1789_cr_out" "")"
run_test "1789_T2.28_cli_exit124_reason" "no_output" "$(kv_value_default REASON "$_1789_cr_out" "")"
run_test "1789_T2.28_cli_exit124_no_flag" "" "$(kv_value_default NO_VERDICT_YET "$_1789_cr_out" "")"
run_test "1789_T2.28_cli_exit124_handler_return" "0" "$(kv_value_default EXIT "$_1789_cr_out" "")"
_1789_reset_processing_globals
reviewer_loop_process_platform_output "coderabbit-cli" 1 "$_1789_cr_out" 0 1 >/dev/null 2>&1
run_test "1789_T2.28_cli_exit124_label_required" "1" "$reviewer_failed_required"
run_test "1789_T2.28_cli_exit124_class" "skipped_failure_evidence" \
  "$(reviewer_loop_platform_outcome_class skipped "$(kv_value_default REASON "$_1789_cr_out" "")" "$(kv_value_default NO_VERDICT_YET "$_1789_cr_out" 0)")"
run_test "1789_T2.28_cli_exit124_no_break" "0" "$reviewer_loop_platform_loop_should_break"
reviewer_loop_process_platform_output "pr-agent" 2 "$(printf 'RESULT=clean\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')" 0 1 >/dev/null 2>&1
run_test "1789_T2.28_cli_exit124_clean_peer_keeps_clean" "clean" "$aggregate_result"
run_test "1789_T2.28_cli_exit124_label_still_required" "1" "$reviewer_failed_required"

_1789_cr_out="$(_1789_run_cr_cli 0 4 1)"
run_test "1789_T2.4_cli_timeout_result" "skipped" "$(kv_value_default RESULT "$_1789_cr_out" "")"
run_test "1789_T2.4_cli_timeout_reason" "timeout" "$(kv_value_default REASON "$_1789_cr_out" "")"
run_test "1789_T2.4_cli_timeout_flag" "1" "$(kv_value_default NO_VERDICT_YET "$_1789_cr_out" "")"
run_test "1789_T2.4_cli_timeout_display" "no verdict yet (non-blocking skip: timeout)" \
  "$(kv_value_default DISPLAY_RESULT "$_1789_cr_out" "")"
run_test "1789_T2.4_cli_timeout_display_once" "1" "$(printf '%s\n' "$_1789_cr_out" | grep -c '^DISPLAY_RESULT=' || true)"
_1789_reset_processing_globals
reviewer_loop_process_platform_output "coderabbit-cli" 1 "$_1789_cr_out" 0 1 >/dev/null 2>&1
run_test "1789_T2.4_cli_timeout_label_not_required" "0" "$reviewer_failed_required"
run_test "1789_T2.4_cli_timeout_aggregate_clean" "clean" "$aggregate_result"
run_test "1789_T2.4_cli_timeout_no_break" "0" "$reviewer_loop_platform_loop_should_break"
run_test "1789_T2.4_cli_timeout_class" "no_verdict_yet" \
  "$(reviewer_loop_platform_outcome_class skipped timeout "$(kv_value_default NO_VERDICT_YET "$_1789_cr_out" 0)")"
run_test "1789_T2.10_cli_timeout_record_no_verdict_yet" "no_verdict_yet" \
  "$(printf '%s\n' "${platform_result_records[@]}" | jq -sr 'last | .result')"
run_test "1789_T2.4_cli_timeout_token" "coderabbit-cli:no verdict yet (non-blocking skip: timeout)" \
  "$(printf '%s\n' "${platform_result_tokens[@]}" | tail -n 1)"

# ---------------------------------------------------------------------------
# Phase 2b — in-loop GitHub-platform handlers (plan D3, D8): Greptile, Devin,
# CodeRabbit, Copilot, Ronda, Bugbot, PR-Agent (T2.1–T2.6, T2.11, T2.24–T2.26).
#
# One endpoint-aware mock gh serves fixtures from a directory. A fixture named
# `<name>@<n>` takes effect once the elapsed counter reaches <n>; the counter
# only advances through the mocked _interruptible_sleep, so budgets of
# thousands of seconds run instantly (time-scaled, T2.2/T2.11). Every "bound to
# H" verdict mock satisfies both today's filters and D15: review comments carry
# commit_id and original_commit_id H, reviews carry commit_id H, everything is
# created after the head commit and the request, and the PR-Agent summary
# carries the H marker line.
# ---------------------------------------------------------------------------
_1789_H="$(printf '1789%036d' 0 | tr 0 d)"
_1789_OLD="$(printf '1789%036d' 0 | tr 0 e)"
_1789_gh_bin="$_1789_dir/gh-bin"
_1789_gh_dir="$_1789_dir/gh-fx"
mkdir -p "$_1789_gh_bin"
cat > "$_1789_gh_bin/gh" <<'MOCK_1789_GH'
#!/usr/bin/env bash
d="${MOCK_1789_GH_DIR:?}"
tick="$(cat "$d/tick" 2>/dev/null || printf '0')"
printf 'tick=%s %s\n' "$tick" "$*" >> "$d/calls.log"
# fixture <name> <fallback>: the newest <name>@<n> with n <= tick, else <name>,
# else the fallback.
fixture() {
  local name="$1" fallback="$2" best="" best_n=-1 f n
  for f in "$d/$name"@*; do
    [ -e "$f" ] || continue
    n="${f##*@}"
    if [ "$n" -le "$tick" ] && [ "$n" -gt "$best_n" ]; then best="$f"; best_n="$n"; fi
  done
  if [ -n "$best" ]; then cat "$best"
  elif [ -e "$d/$name" ]; then cat "$d/$name"
  else printf '%s\n' "$fallback"; fi
}
jq_expr=""; prev=""
for a in "$@"; do
  [ "$prev" = "--jq" ] && jq_expr="$a"
  prev="$a"
done
head="$(cat "$d/head")"
# Read refusals (#1789 BR 2): each gh-error line `<substring>|<stderr text>`
# makes the first matching non-POST call print <stderr text> and exit 1.
if [ -e "$d/gh-error" ]; then
  case "$*" in
    *"--method POST"*|*"-X POST"*|"pr comment"*) ;;
    *)
      while IFS='|' read -r pat msg; do
        [ -n "$pat" ] || continue
        case "$*" in
          *"$pat"*) printf '%s\n' "$msg" >&2; exit 1 ;;
        esac
      done < "$d/gh-error"
      ;;
  esac
fi
case "$*" in
  *"--method POST"*|*"-X POST"*|"pr comment"*)
    printf 'tick=%s %s\n' "$tick" "$*" >> "$d/posts.log"
    [ "$(fixture post-exit 0)" = "0" ] || exit 1
    out="$(fixture post-body '{"id":9001,"created_at":"2020-01-01T00:00:05Z"}')"
    ;;
  "api user"*) out='{"login":"runner"}' ;;
  "pr view"*) out="$(fixture pr-view "{\"headRefOid\":\"$head\"}")" ;;
  *"/check-runs"*)
    [ "$(fixture check-runs-fail 0)" = "0" ] || exit 1
    all_args="$*"; sha="${all_args#*commits/}"; sha="${sha%%/*}"
    if [ -e "$d/check-runs.$sha" ]; then out="$(cat "$d/check-runs.$sha")"
    else out="$(fixture check-runs '{"check_runs":[]}')"; fi
    ;;
  *"/statuses"*)
    [ "$(fixture statuses-fail 0)" = "0" ] || exit 1
    out="$(fixture statuses '[]')"
    ;;
  *"/reactions"*)
    all_args="$*"; cid="${all_args#*comments/}"; cid="${cid%%/*}"
    [ -e "$d/reactions-fail.$cid" ] && exit 1
    out="$(fixture "reactions.$cid" "$(fixture reactions '[]')")"
    ;;
  *"/pulls/42/comments"*) out="$(fixture review-comments '[]')" ;;
  *"/pulls/42/reviews"*) out="$(fixture reviews '[]')" ;;
  *"/issues/42/comments"*) out="$(fixture issue-comments '[]')" ;;
  *"actions/runs?check_suite_id="*)
    [ "$(fixture suite-runs-fail 0)" = "0" ] || exit 1
    out="$(fixture suite-runs '{"workflow_runs":[{"id":3001,"workflow_id":77}]}')"
    ;;
  *"actions/workflows/"*"/runs"*)
    [ "$(fixture branch-runs-fail 0)" = "0" ] || exit 1
    out="$(fixture branch-runs '{"workflow_runs":[]}')"
    ;;
  *"/pulls/42"*)
    [ "$(fixture pull-fail 0)" = "0" ] || exit 1
    out="{\"head\":{\"sha\":\"$head\",\"ref\":\"feature/1789-x\"}}"
    ;;
  *"/commits/"*) out='{"commit":{"committer":{"date":"2020-01-01T00:00:00Z"}}}' ;;
  *) out='[]' ;;
esac
if [ -n "$jq_expr" ]; then
  printf '%s\n' "$out" | jq -r "$jq_expr"
else
  printf '%s\n' "$out"
fi
MOCK_1789_GH
chmod +x "$_1789_gh_bin/gh"

_1789_gh_reset() {
  rm -rf "$_1789_gh_dir"
  mkdir -p "$_1789_gh_dir"
  printf '0\n' > "$_1789_gh_dir/tick"
  printf '%s\n' "$_1789_H" > "$_1789_gh_dir/head"
  : > "$_1789_gh_dir/calls.log"
  : > "$_1789_gh_dir/posts.log"
}
# _1789_fx <name[@tick]> <json>
_1789_fx() { printf '%s\n' "$2" > "$_1789_gh_dir/$1"; }
_1789_tick() { cat "$_1789_gh_dir/tick"; }
_1789_posts() { grep -c '' "$_1789_gh_dir/posts.log" || true; }
# _1789_run_gh <handler> <budget> [poll]: runs a handler against the fixture
# mock and prints its output followed by EXIT=<return status>.
_1789_run_gh() {
  (
    eval "$_1789_handler_overrides"
    _interruptible_sleep() {
      local _t
      _t="$(cat "$_1789_gh_dir/tick")"
      printf '%s\n' "$(( _t + ${1:-0} ))" > "$_1789_gh_dir/tick"
    }
    export MOCK_1789_GH_DIR="$_1789_gh_dir"
    export PATH="$_1789_gh_bin:$PATH"
    export CODERABBIT_NO_TRIGGER_TIMEOUT="${_1789_cr_no_trigger_timeout:-999999}" FALLBACK_THREAD_SETTLE_WAIT=0
    unset PR_REVIEW_TRIGGER_AUTHOR_LOGIN COPILOT_BOT_LOGIN BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME
    unset BUGBOT_TRIGGER_COMMENT PR_AGENT_BOT_LOGIN RONDA_CHECK_NAME PR_AGENT_TRIGGER_REUSE_WINDOW_SECONDS
    loop_head_sha="${_1789_gh_loop_head-$_1789_H}"
    _ec=0
    "$1" "42" "feature/1789-x" "${3:-1}" "$2" 2>"$_1789_gh_dir/stderr" || _ec=$?
    printf 'EXIT=%s\n' "$_ec"
  )
}
_1789_rre() {
  printf '%s|%s|%s' "$(kv_value_default RESULT "$1" "")" "$(kv_value_default REASON "$1" "")" "$(kv_value_default EXIT "$1" "")"
}
# _1789_assert_waiting <tag> <platform> <output> <detail> <head>: the D8 No
# verdict yet block, and the loop records it as waiting, breaks, and does not
# require reviewer-failed (T2.1).
_1789_assert_waiting() {
  local tag="$1" platform="$2" out="$3" detail="$4" head="$5"
  run_test "1789_${tag}_result" "waiting_on_reviewer|reviewer-no-verdict-yet|4|1" \
    "$(_1789_rre "$out")|$(kv_value_default NO_VERDICT_YET "$out" "")"
  run_test "1789_${tag}_detail" "$detail" "$(kv_value_default WAIT_EXPIRED_DETAIL "$out" "")"
  run_test "1789_${tag}_pending" "${platform}|${head}" \
    "$(kv_value_default PENDING_REVIEWER "$out" "")|$(kv_value_default PENDING_REVIEW_HEAD_SHA "$out" "")"
  _1789_reset_processing_globals
  reviewer_loop_process_platform_output "$platform" 1 "$out" 4 1 >/dev/null 2>&1
  run_test "1789_${tag}_aggregate_waiting_breaks_no_label" "waiting_on_reviewer|reviewer-no-verdict-yet|1|0" \
    "${aggregate_result}|${aggregate_reason}|${reviewer_loop_platform_loop_should_break}|${reviewer_failed_required}"
  run_test "1789_${tag}_ledger_no_verdict_yet" "no_verdict_yet" \
    "$(printf '%s\n' "${platform_result_records[@]}" | jq -sr 'last | .result')"
}
# _1789_assert_kept_skip <tag> <platform> <output> <reason> (T2.4)
_1789_assert_kept_skip() {
  local tag="$1" platform="$2" out="$3" reason="$4"
  run_test "1789_${tag}_result" "skipped|${reason}|0|1" \
    "$(_1789_rre "$out")|$(kv_value_default NO_VERDICT_YET "$out" "")"
  run_test "1789_${tag}_display" "no verdict yet (non-blocking skip: ${reason})" \
    "$(kv_value_default DISPLAY_RESULT "$out" "")"
  run_test "1789_${tag}_class" "no_verdict_yet" \
    "$(reviewer_loop_platform_outcome_class skipped "$reason" "$(kv_value_default NO_VERDICT_YET "$out" 0)")"
  _1789_reset_processing_globals
  reviewer_loop_process_platform_output "$platform" 1 "$out" 0 1 >/dev/null 2>&1
  run_test "1789_${tag}_aggregate_clean_no_break_no_label" "clean|0|0" \
    "${aggregate_result}|${reviewer_loop_platform_loop_should_break}|${reviewer_failed_required}"
  run_test "1789_${tag}_ledger_no_verdict_yet" "no_verdict_yet" \
    "$(printf '%s\n' "${platform_result_records[@]}" | jq -sr 'last | .result')"
}
# _1789_assert_failed <tag> <platform> <output> <reason>: failure evidence
# stays escalate, class reviewer_failed, and requires the label (T2.3).
_1789_assert_failed() {
  local tag="$1" platform="$2" out="$3" reason="$4"
  run_test "1789_${tag}_result" "escalate|${reason}|2" "$(_1789_rre "$out")"
  run_test "1789_${tag}_class" "reviewer_failed" "$(reviewer_loop_platform_outcome_class escalate "$reason" 0)"
  run_test "1789_${tag}_label_required" "yes" "$(_1789_label escalate "$reason")"
  _1789_reset_processing_globals
  reviewer_loop_process_platform_output "$platform" 1 "$out" 2 1 >/dev/null 2>&1
  run_test "1789_${tag}_process_requires_label" "1" "$reviewer_failed_required"
}

# --- Greptile
_1789_gh_reset
_1789_out="$(_1789_run_gh run_greptile_review 2)"
_1789_assert_waiting T2.1_greptile greptile "$_1789_out" no_acknowledgement "$_1789_H"
run_test "1789_T2.1_greptile_posted_once" "1" "$(_1789_posts)"
run_test "1789_T2.1_greptile_bounded_by_budget" "2" "$(_1789_tick)"
# Kept failure path: no trigger comment id from the POST → exit 2, never waiting.
_1789_gh_reset
_1789_fx post-body ''
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T2.3_greptile_missing_trigger_id_exit2" "2|" \
  "$(kv_value_default EXIT "$_1789_out" "")|$(kv_value_default NO_VERDICT_YET "$_1789_out" "")"

# --- Copilot
_1789_gh_reset
_1789_out="$(_1789_run_gh run_copilot_review 2)"
_1789_assert_waiting T2.1_copilot copilot "$_1789_out" review_not_submitted "$_1789_H"
# T2.5: an APPROVED review on another revision is not evidence for H.
_1789_gh_reset
_1789_fx reviews "[{\"user\":{\"login\":\"copilot-pull-request-reviewer[bot]\"},\"state\":\"APPROVED\",\"commit_id\":\"$_1789_OLD\",\"submitted_at\":\"2020-01-01T00:00:09Z\"}]"
_1789_out="$(_1789_run_gh run_copilot_review 2)"
run_test "1789_T2.5_copilot_older_review_no_verdict_yet" "waiting_on_reviewer|reviewer-no-verdict-yet|4" "$(_1789_rre "$_1789_out")"
# The same review bound to H is today's verdict.
_1789_fx reviews "[{\"user\":{\"login\":\"copilot-pull-request-reviewer[bot]\"},\"state\":\"APPROVED\",\"commit_id\":\"$_1789_H\",\"submitted_at\":\"2020-01-01T00:00:09Z\"}]"
_1789_out="$(_1789_run_gh run_copilot_review 2)"
run_test "1789_T2.5_copilot_bound_review_clean" "clean||0" "$(_1789_rre "$_1789_out")"
# T2.6: the reviewer request failing keeps its failure handling.
_1789_gh_reset
_1789_fx post-exit 1
_1789_out="$(_1789_run_gh run_copilot_review 2)"
_1789_assert_failed T2.6_copilot_request_failure copilot "$_1789_out" unavailable

# --- Ronda
_1789_gh_reset
_1789_out="$(_1789_run_gh run_ronda_review 2)"
_1789_assert_waiting T2.1_ronda ronda "$_1789_out" check_not_completed "$_1789_H"
_1789_gh_reset
_1789_fx check-runs '{"check_runs":[{"id":31,"name":"Ronda review","status":"completed","conclusion":"failure","started_at":"2020-01-01T00:00:02Z","output":{"title":"model unavailable"}}]}'
_1789_out="$(_1789_run_gh run_ronda_review 2)"
_1789_assert_failed T2.3_ronda_pass_failed ronda "$_1789_out" ronda_pass_failed

# --- Bugbot
_1789_bb_run() {
  printf '{"check_runs":[{"id":%s,"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"%s","conclusion":%s,"started_at":"2020-01-01T00:00:0%s"}]}' "$1" "$2" "$3" "$4"
}
# T2.1: a run appears but never completes → check_not_completed, the one
# re-trigger fires inside the budget, and the wait is bounded by the budget.
_1789_gh_reset
_1789_fx check-runs "$(_1789_bb_run 21 in_progress null 1)"
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
_1789_assert_waiting T2.1_bugbot_not_completed bugbot "$_1789_out" check_not_completed "$_1789_H"
run_test "1789_T2.1_bugbot_not_completed_one_retrigger" "1" "$(_1789_posts)"
run_test "1789_T2.1_bugbot_not_completed_bounded" "4" "$(_1789_tick)"
# T2.1: no run ever appears → check_not_started (initial trigger + one re-trigger).
_1789_gh_reset
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
_1789_assert_waiting T2.1_bugbot_not_started bugbot "$_1789_out" check_not_started "$_1789_H"
run_test "1789_T2.1_bugbot_not_started_trigger_and_retrigger" "2" "$(_1789_posts)"
run_test "1789_T2.1_bugbot_not_started_retrigger_at_d3_point" "tick=2" \
  "$(sed -n '2p' "$_1789_gh_dir/posts.log" | cut -d' ' -f1)"
# T2.11: default budget 2400, poll 120: exactly one re-trigger, at elapsed
# 1800 (= 2400 - min(600, 1200)), and the total wait ends at the budget.
_1789_gh_reset
_1789_fx check-runs "$(_1789_bb_run 22 in_progress null 1)"
_1789_out="$(_1789_run_gh run_bugbot_review 2400 120)"
run_test "1789_T2.11_bugbot_result" "waiting_on_reviewer|reviewer-no-verdict-yet|4" "$(_1789_rre "$_1789_out")"
run_test "1789_T2.11_bugbot_exactly_one_retrigger" "1" "$(_1789_posts)"
run_test "1789_T2.11_bugbot_retrigger_at_1800" "tick=1800" "$(cut -d' ' -f1 "$_1789_gh_dir/posts.log")"
run_test "1789_T2.11_bugbot_total_wait_bounded" "2400" "$(_1789_tick)"
# Small budgets: the re-trigger point is budget - min(600, floor(budget/2)).
_1789_gh_reset
_1789_fx check-runs "$(_1789_bb_run 23 in_progress null 1)"
_1789_out="$(_1789_run_gh run_bugbot_review 1000 100)"
run_test "1789_T2.11_bugbot_retrigger_point_1000" "tick=500" "$(cut -d' ' -f1 "$_1789_gh_dir/posts.log")"
# T2.2: implementation-plan branch, no override → budget 2400 (D2) and poll 30
# (D14); a run that completes success at elapsed 1500 is clean, and no
# re-trigger is posted (the only POST is the initial request at elapsed 0).
_1789_saved_t22_branch="$branch_name"
branch_name="implementation-plan/1789-x"
config_file="$_1789_none_cfg"
read -r _1789_t22_budget _1789_t22_src _1789_t22_adj <<<"$(reviewer_wait_budget_resolve bugbot)"
_1789_t22_poll="$(reviewer_poll_interval_resolve bugbot "$_1789_t22_budget")"
branch_name="$_1789_saved_t22_branch"
run_test "1789_T2.2_bugbot_budget_and_poll" "2400 default none 30" \
  "$_1789_t22_budget $_1789_t22_src $_1789_t22_adj $_1789_t22_poll"
_1789_gh_reset
_1789_fx check-runs@30 "$(_1789_bb_run 24 in_progress null 1)"
_1789_fx check-runs@1500 "$(_1789_bb_run 24 completed '"success"' 1)"
_1789_out="$(_1789_run_gh run_bugbot_review "$_1789_t22_budget" "$_1789_t22_poll")"
run_test "1789_T2.2_bugbot_clean_at_1500" "clean||0" "$(_1789_rre "$_1789_out")"
run_test "1789_T2.2_bugbot_observed_at_1500" "1500" "$(_1789_tick)"
run_test "1789_T2.2_bugbot_no_retrigger" "1|tick=0" \
  "$(_1789_posts)|$(cut -d' ' -f1 "$_1789_gh_dir/posts.log")"
# T2.3: Bugbot's own timed_out run → escalate/bugbot-run-timed-out.
_1789_gh_reset
_1789_fx check-runs "$(_1789_bb_run 25 completed '"timed_out"' 1)"
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
_1789_assert_failed T2.3_bugbot_run_timed_out bugbot "$_1789_out" bugbot-run-timed-out
run_test "1789_T2.3_bugbot_run_timed_out_compare_token" "timed out" \
  "$(normalize_platform_verdict escalate "REASON=bugbot-run-timed-out")"
# T2.5: a completed success run on another revision is never H's verdict.
_1789_gh_reset
_1789_fx "check-runs.$_1789_OLD" "$(_1789_bb_run 26 completed '"success"' 1)"
_1789_out="$(_1789_run_gh run_bugbot_review 2)"
run_test "1789_T2.5_bugbot_other_revision_run_no_verdict_yet" "waiting_on_reviewer|reviewer-no-verdict-yet|4|check_not_started" \
  "$(_1789_rre "$_1789_out")|$(kv_value_default WAIT_EXPIRED_DETAIL "$_1789_out" "")"
# T2.6: Bugbot's own "disabled" self-report keeps its failure handling.
_1789_gh_reset
_1789_fx issue-comments '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-01T00:00:02Z","body":"Bugbot is disabled for this repository."}]'
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
_1789_assert_failed T2.6_bugbot_disabled bugbot "$_1789_out" bugbot-disabled

# --- Devin (T2.1, T2.4, T2.24)
_1789_dv_run() {
  printf '{"check_runs":[{"id":41,"name":"Devin Review","app":{"slug":"devin-ai-integration"},"status":"%s","conclusion":%s,"started_at":"2020-01-01T00:00:01Z"}]}' "$1" "$2"
}
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run in_progress null)"
_1789_out="$(_1789_run_gh run_devin_review 2)"
_1789_assert_waiting T2.1_devin devin "$_1789_out" check_not_completed "$_1789_H"
_1789_gh_reset
_1789_out="$(_1789_run_gh run_devin_review 2)"
_1789_assert_kept_skip T2.4_devin_no_check_run devin "$_1789_out" no_check_run
# T2.24: a timed-out Devin check with no findings → devin_run_failed after the grace.
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run completed '"timed_out"')"
_1789_out="$(_1789_run_gh run_devin_review 300 60)"
_1789_assert_failed T2.24_devin_timed_out_check devin "$_1789_out" devin_run_failed
run_test "1789_T2.24_devin_timed_out_check_after_grace" "120" "$(_1789_tick)"
# Variant: a Devin status in `error` with no findings.
_1789_gh_reset
_1789_fx statuses '[{"id":3,"context":"Devin Review","state":"error","created_at":"2020-01-01T00:00:02Z"}]'
_1789_out="$(_1789_run_gh run_devin_review 300 60)"
_1789_assert_failed T2.24_devin_error_status devin "$_1789_out" devin_run_failed
# Variant: a failure check with a finding bound to H → needs_fixes.
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run completed '"failure"')"
_1789_fx review-comments@60 "[{\"id\":77,\"user\":{\"login\":\"devin-ai-integration[bot]\"},\"created_at\":\"2020-01-01T00:01:00Z\",\"in_reply_to_id\":null,\"path\":\"a.sh\",\"line\":3,\"body\":\"Bug: off-by-one in the loop bound\",\"commit_id\":\"$_1789_H\",\"original_commit_id\":\"$_1789_H\"}]"
_1789_out="$(_1789_run_gh run_devin_review 300 60)"
run_test "1789_T2.24_devin_failure_check_with_finding_needs_fixes" "needs_fixes||1" "$(_1789_rre "$_1789_out")"
# Variant: a bound "No Issues Found" review plus a timed_out check → today's clean.
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run completed '"timed_out"')"
_1789_fx reviews "[{\"id\":5,\"user\":{\"login\":\"devin-ai-integration[bot]\"},\"state\":\"COMMENTED\",\"submitted_at\":\"2020-01-01T00:00:30Z\",\"commit_id\":\"$_1789_H\",\"body\":\"No Issues Found\"}]"
_1789_out="$(_1789_run_gh run_devin_review 300 60)"
run_test "1789_T2.24_devin_bound_review_keeps_clean" "clean||0" "$(_1789_rre "$_1789_out")"
# Variant: a success check with no findings → clean as today.
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run completed '"success"')"
_1789_out="$(_1789_run_gh run_devin_review 300 60)"
run_test "1789_T2.24_devin_success_check_clean" "clean||0" "$(_1789_rre "$_1789_out")"
# Variant: the budget ends inside the 120 s grace after a timed_out check →
# devin_run_failed, never No verdict yet.
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run completed '"timed_out"')"
_1789_out="$(_1789_run_gh run_devin_review 60 30)"
_1789_assert_failed T2.24_devin_expiry_inside_grace devin "$_1789_out" devin_run_failed
# Contrast: the budget ends inside the grace after a success check → No verdict yet.
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run completed '"success"')"
_1789_out="$(_1789_run_gh run_devin_review 60 30)"
run_test "1789_T2.24_devin_success_inside_grace_no_verdict_yet" "waiting_on_reviewer|reviewer-no-verdict-yet|4|check_not_completed" \
  "$(_1789_rre "$_1789_out")|$(kv_value_default WAIT_EXPIRED_DETAIL "$_1789_out" "")"
# Failed polling reads keep the last successful read in force (plan D8): a
# timed_out check / error status observed once is not forgotten when later
# reads fail, and a once-seen in-progress check is not "no check ever seen".
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run completed '"timed_out"')"
_1789_fx check-runs-fail@30 1
_1789_out="$(_1789_run_gh run_devin_review 60 30)"
_1789_assert_failed T2.24_devin_timed_out_then_failed_reads devin "$_1789_out" devin_run_failed
run_test "1789_T2.24_devin_timed_out_then_failed_reads_exit" "escalate|devin_run_failed|2" "$(_1789_rre "$_1789_out")"
_1789_gh_reset
_1789_fx statuses '[{"id":3,"context":"Devin Review","state":"error","created_at":"2020-01-01T00:00:02Z"}]'
_1789_fx statuses-fail@30 1
_1789_out="$(_1789_run_gh run_devin_review 60 30)"
run_test "1789_T2.24_devin_error_status_then_failed_reads" "escalate|devin_run_failed|2" "$(_1789_rre "$_1789_out")"
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run in_progress null)"
_1789_fx check-runs-fail@30 1
_1789_out="$(_1789_run_gh run_devin_review 60 30)"
run_test "1789_T2.24_devin_seen_check_then_failed_reads_no_verdict_yet" \
  "waiting_on_reviewer|reviewer-no-verdict-yet|4|check_not_completed" \
  "$(_1789_rre "$_1789_out")|$(kv_value_default WAIT_EXPIRED_DETAIL "$_1789_out" "")"
# A later successful read supersedes the retained evidence (timed_out then a
# success run on the same check).
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run completed '"timed_out"')"
_1789_fx check-runs@30 "$(_1789_dv_run completed '"success"')"
_1789_out="$(_1789_run_gh run_devin_review 60 30)"
run_test "1789_T2.24_devin_successful_read_supersedes_failure" \
  "waiting_on_reviewer|reviewer-no-verdict-yet|4" "$(_1789_rre "$_1789_out")"

# --- CodeRabbit (T2.4, T2.25)
_1789_cr_status() {
  printf '[{"id":%s,"context":"CodeRabbit","state":"%s","description":"%s","created_at":"2020-01-01T00:00:0%s"}]' "$1" "$2" "$3" "$4"
}
_1789_gh_reset
_1789_out="$(_1789_run_gh run_coderabbit_review 3)"
_1789_assert_kept_skip T2.4_coderabbit_no_review coderabbit "$_1789_out" no_review
# T2.25: a failure (and an error) status on H with no bound review or finding.
for _1789_state in failure error; do
  _1789_gh_reset
  _1789_fx statuses "$(_1789_cr_status 8 "$_1789_state" "Review failed" 3)"
  _1789_out="$(_1789_run_gh run_coderabbit_review 5)"
  _1789_assert_failed "T2.25_coderabbit_status_${_1789_state}" coderabbit "$_1789_out" coderabbit_status_failed
  run_test "1789_T2.25_coderabbit_status_${_1789_state}_ends_wait" "0" "$(_1789_tick)"
done
# With an H-bound finding → needs_fixes.
_1789_gh_reset
_1789_fx statuses@1 "$(_1789_cr_status 8 failure "Review failed" 3)"
_1789_fx review-comments@1 "[{\"id\":78,\"user\":{\"login\":\"coderabbitai[bot]\"},\"created_at\":\"2020-01-01T00:00:20Z\",\"in_reply_to_id\":null,\"path\":\"a.sh\",\"line\":4,\"body\":\"🔴 Critical: unquoted expansion\",\"commit_id\":\"$_1789_H\",\"original_commit_id\":\"$_1789_H\"}]"
_1789_out="$(_1789_run_gh run_coderabbit_review 5)"
run_test "1789_T2.25_coderabbit_failed_status_with_finding_needs_fixes" "needs_fixes||1" "$(_1789_rre "$_1789_out")"
# A review bound to H (commit_id == H) keeps today's verdict.
_1789_gh_reset
_1789_fx statuses "$(_1789_cr_status 8 failure "Review failed" 3)"
_1789_fx reviews "[{\"id\":6,\"user\":{\"login\":\"coderabbitai[bot]\"},\"state\":\"COMMENTED\",\"submitted_at\":\"2020-01-01T00:00:00Z\",\"commit_id\":\"$_1789_H\",\"body\":\"Summary\"}]"
_1789_out="$(_1789_run_gh run_coderabbit_review 5)"
run_test "1789_T2.25_coderabbit_failed_status_bound_review_keeps_verdict" "clean||0" "$(_1789_rre "$_1789_out")"
# A failure status in the #1437 rate/review-limit wording is not counted.
_1789_gh_reset
_1789_fx statuses "$(_1789_cr_status 8 failure "Review limit reached. Next review available in: 30 minutes" 3)"
_1789_out="$(_1789_run_gh run_coderabbit_review 3)"
run_test "1789_T2.25_coderabbit_rate_limit_failure_status_not_counted" "skipped|no_review|0" "$(_1789_rre "$_1789_out")"
# Unit rows for the counter (newest state per context governs).
_1789_cr_count() {
  (
    export MOCK_1789_GH_DIR="$_1789_gh_dir"
    export PATH="$_1789_gh_bin:$PATH"
    coderabbit_failed_status_count "$@"
  )
}
_1789_gh_reset
_1789_fx statuses "$(_1789_cr_status 8 failure "Review failed" 3)"
run_test "1789_T2.25_failed_status_count_failure" "1" "$(_1789_cr_count owner/repo "$_1789_H")"
_1789_fx statuses "$(_1789_cr_status 8 failure "Rate limit exceeded" 3)"
run_test "1789_T2.25_failed_status_count_rate_limit_excluded" "0" "$(_1789_cr_count owner/repo "$_1789_H")"
_1789_fx statuses '[{"id":9,"context":"CodeRabbit","state":"success","description":"Review completed","created_at":"2020-01-01T00:00:09Z"},{"id":8,"context":"CodeRabbit","state":"failure","description":"Review failed","created_at":"2020-01-01T00:00:03Z"}]'
run_test "1789_T2.25_failed_status_count_newer_success_governs" "0" "$(_1789_cr_count owner/repo "$_1789_H")"
_1789_fx statuses '[{"id":9,"context":"CodeRabbit","state":"error","description":"Review errored","created_at":"2020-01-01T00:00:09Z"},{"id":8,"context":"CodeRabbit","state":"success","description":"Review completed","created_at":"2020-01-01T00:00:03Z"}]'
run_test "1789_T2.25_failed_status_count_newer_error_governs" "1" "$(_1789_cr_count owner/repo "$_1789_H")"
_1789_fx statuses 'not json'
run_test "1789_T2.25_failed_status_count_unreadable_is_zero" "0" "$(_1789_cr_count owner/repo "$_1789_H")"
run_test "1789_T2.25_failed_status_count_missing_args_zero" "0" "$(_1789_cr_count "" "")"

# --- PR-Agent (T2.4, T2.26)
_1789_pra() {
  printf '{"id":%s,"name":"PR-Agent review","status":"%s","conclusion":%s,"started_at":"2020-01-01T00:00:%s"}' "$1" "$2" "$3" "$4"
}
_1789_pra_runs() { printf '{"check_runs":[%s]}' "$1"; }
_1789_gh_reset
_1789_out="$(_1789_run_gh run_pr_agent_review 3)"
_1789_assert_kept_skip T2.4_pr_agent_no_review pr-agent "$_1789_out" no_review
run_test "1789_T2.4_pr_agent_posted_request" "1" "$(_1789_posts)"
# T2.26: a run on H active at Phase 1 (no /review posted), then it completes
# cancelled (and, separately, timed_out) → pr_agent_run_failed on that poll.
for _1789_concl in cancelled timed_out; do
  _1789_gh_reset
  _1789_fx check-runs "$(_1789_pra_runs "$(_1789_pra 10 in_progress null 10)")"
  _1789_fx check-runs@1 "$(_1789_pra_runs "$(_1789_pra 10 completed "\"$_1789_concl\"" 10)")"
  _1789_out="$(_1789_run_gh run_pr_agent_review 5)"
  _1789_assert_failed "T2.26_pr_agent_active_then_${_1789_concl}" pr-agent "$_1789_out" pr_agent_run_failed
  run_test "1789_T2.26_pr_agent_active_then_${_1789_concl}_no_post" "0" "$(_1789_posts)"
  run_test "1789_T2.26_pr_agent_active_then_${_1789_concl}_returns_on_that_poll" "1" "$(_1789_tick)"
  run_test "1789_T2.26_pr_agent_active_then_${_1789_concl}_conclusion" "$_1789_concl" \
    "$(kv_value_default PR_AGENT_RUN_CONCLUSION "$_1789_out" "")"
done
# Regression: a run on H that already completed timed_out before Phase 1. The
# handler posts /review (an outstanding request), no poll returns before the
# budget, and the result at the budget is pr_agent_run_failed, never the kept skip.
_1789_gh_reset
_1789_fx check-runs "$(_1789_pra_runs "$(_1789_pra 10 completed '"timed_out"' 10)")"
_1789_out="$(_1789_run_gh run_pr_agent_review 5)"
_1789_assert_failed T2.26_pr_agent_pre_failed pr-agent "$_1789_out" pr_agent_run_failed
run_test "1789_T2.26_pr_agent_pre_failed_posted_request" "1" "$(_1789_posts)"
run_test "1789_T2.26_pr_agent_pre_failed_waits_full_budget" "5" "$(_1789_tick)"
# Supersession: a newer run on H (later started_at, higher id) appears and
# completes success with no bound summary → the no_review kept skip.
_1789_gh_reset
_1789_fx check-runs "$(_1789_pra_runs "$(_1789_pra 10 completed '"timed_out"' 10)")"
_1789_fx check-runs@2 "$(_1789_pra_runs "$(_1789_pra 10 completed '"timed_out"' 10),$(_1789_pra 11 in_progress null 20)")"
_1789_fx check-runs@3 "$(_1789_pra_runs "$(_1789_pra 10 completed '"timed_out"' 10),$(_1789_pra 11 completed '"success"' 20)")"
_1789_out="$(_1789_run_gh run_pr_agent_review 5)"
run_test "1789_T2.26_pr_agent_superseded_by_newer_run_kept_skip" "skipped|no_review|0|1" \
  "$(_1789_rre "$_1789_out")|$(kv_value_default NO_VERDICT_YET "$_1789_out" "")"
# ...and a summary that then carries the H marker is the verdict.
_1789_fx issue-comments@4 "[{\"id\":501,\"user\":{\"login\":\"github-actions[bot]\"},\"created_at\":\"2020-01-01T00:00:30Z\",\"updated_at\":\"2020-01-01T00:00:40Z\",\"html_url\":\"https://github.com/owner/repo/pull/42#issuecomment-501\",\"body\":\"## PR Reviewer Guide 🔍\\n\\n#### (Review updated until commit https://github.com/owner/repo/commit/$_1789_H)\\n\\nNo major issues detected\"}]"
_1789_out="$(_1789_run_gh run_pr_agent_review 6)"
run_test "1789_T2.26_pr_agent_bound_summary_is_verdict" "clean||0" "$(_1789_rre "$_1789_out")"
# A failure-type run on another revision (the default-branch tip an
# issue_comment run reports) is never read: only commits/H/check-runs is read.
_1789_gh_reset
_1789_fx "check-runs.$_1789_OLD" "$(_1789_pra_runs "$(_1789_pra 12 completed '"failure"' 10)")"
_1789_out="$(_1789_run_gh run_pr_agent_review 3)"
run_test "1789_T2.26_pr_agent_other_revision_failure_not_read" "skipped|no_review|0" "$(_1789_rre "$_1789_out")"
run_test "1789_T2.26_pr_agent_reads_only_head_check_runs" "0" \
  "$(grep 'check-runs' "$_1789_gh_dir/calls.log" | grep -vc "commits/$_1789_H/check-runs" || true)"
# A per-poll read that fails on every poll gives the kept skip.
_1789_gh_reset
_1789_fx check-runs-fail 1
_1789_out="$(_1789_run_gh run_pr_agent_review 3)"
run_test "1789_T2.26_pr_agent_read_always_fails_kept_skip" "skipped|no_review|0" "$(_1789_rre "$_1789_out")"
# One failing poll after a failure-type read keeps pr_agent_run_failed at the budget.
_1789_gh_reset
_1789_fx check-runs "$(_1789_pra_runs "$(_1789_pra 10 completed '"timed_out"' 10)")"
_1789_fx check-runs-fail@2 1
_1789_out="$(_1789_run_gh run_pr_agent_review 5)"
run_test "1789_T2.26_pr_agent_failed_read_keeps_last_signal" "escalate|pr_agent_run_failed|2" "$(_1789_rre "$_1789_out")"

# ---------------------------------------------------------------------------
# Phase 5 — current-revision binding (plan D15): T2.16 (review-comment drift)
# and T2.17 (completion signals) for Bugbot, Devin, and CodeRabbit. A
# "drifted" comment is an older head's review comment that GitHub moved to the
# current head: commit_id H, original_commit_id OLD, created after every time
# filter. It is never H's finding; the same comment with original_commit_id H
# is.
# ---------------------------------------------------------------------------
# _1789_rc <id> <login> <commit_id> <original_commit_id> <body> [created_at]
_1789_rc() {
  jq -nc --argjson id "$1" --arg login "$2" --arg c "$3" --arg o "$4" --arg body "$5" \
    --arg at "${6:-2020-01-01T00:00:20Z}" \
    '{id: $id, user: {login: $login}, created_at: $at, in_reply_to_id: null, path: "a.sh", line: 7,
      body: $body, commit_id: $c, original_commit_id: $o}'
}
_1789_bb_check() {
  printf '{"check_runs":[{"id":%s,"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"%s","started_at":"2020-01-01T00:00:01Z","output":{"summary":"%s"}}]}' \
    "$1" "$2" "${3:-}"
}
_1789_bb_finding="BUGBOT_REVIEW: null pointer dereference"

# --- T2.16 Bugbot: Phase 1 existing findings.
_1789_gh_reset
_1789_fx review-comments "[$(_1789_rc 601 "cursor[bot]" "$_1789_H" "$_1789_OLD" "$_1789_bb_finding")]"
_1789_fx check-runs "$(_1789_bb_check 61 success)"
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
run_test "1789_T2.16_bugbot_drifted_comment_ignored_clean" "clean||0" "$(_1789_rre "$_1789_out")"
_1789_fx review-comments "[$(_1789_rc 602 "cursor[bot]" "$_1789_H" "$_1789_H" "$_1789_bb_finding")]"
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
run_test "1789_T2.16_bugbot_bound_comment_phase1_needs_fixes" "needs_fixes|1" \
  "$(kv_value_default RESULT "$_1789_out" "")|$(kv_value_default EXIT "$_1789_out" "")"
# --- T2.16 Bugbot: the success-conclusion inspection (comments appear after Phase 1).
_1789_gh_reset
_1789_fx check-runs "$(_1789_bb_check 62 success)"
_1789_fx review-comments@1 "[$(_1789_rc 603 "cursor[bot]" "$_1789_H" "$_1789_OLD" "$_1789_bb_finding")]"
_1789_fx check-runs@1 "$(_1789_bb_check 62 success)"
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
run_test "1789_T2.16_bugbot_success_path_drifted_ignored" "clean|0" \
  "$(kv_value_default RESULT "$_1789_out" "")|$(kv_value_default BLOCKING_COUNT "$_1789_out" "")"
# --- T2.16 Bugbot: the failure-conclusion collection — a drifted comment is
# not surfaced as this head's finding (only the synthetic blocker remains).
_1789_gh_reset
_1789_fx check-runs "$(_1789_bb_check 63 failure)"
_1789_fx review-comments "[$(_1789_rc 604 "cursor[bot]" "$_1789_H" "$_1789_OLD" "$_1789_bb_finding")]"
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
run_test "1789_T2.16_bugbot_failure_path_drifted_body_not_surfaced" "0" \
  "$(printf '%s\n' "$_1789_out" | grep -c 'null pointer dereference' || true)"
_1789_fx review-comments "[$(_1789_rc 605 "cursor[bot]" "$_1789_H" "$_1789_H" "$_1789_bb_finding")]"
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
run_test "1789_T2.16_bugbot_failure_path_bound_body_surfaced" "needs_fixes|yes" \
  "$(kv_value_default RESULT "$_1789_out" "")|$( [ "$(printf '%s\n' "$_1789_out" | grep -c 'null pointer dereference' || true)" -ge 1 ] && echo yes || echo no)"
# --- T2.16 Bugbot: the neutral-conclusion collection — a summary that reports
# a finding with only a drifted comment is not retrievable for this head.
_1789_gh_reset
_1789_fx check-runs "$(_1789_bb_check 64 neutral 'Final Result: Bugbot completed review and found 1 potential issue.')"
_1789_fx review-comments "[$(_1789_rc 606 "cursor[bot]" "$_1789_H" "$_1789_OLD" "**High Severity** $_1789_bb_finding")]"
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
run_test "1789_T2.16_bugbot_neutral_path_drifted_not_retrievable" "escalate|bugbot-findings-not-retrievable" \
  "$(kv_value_default RESULT "$_1789_out" "")|$(kv_value_default REASON "$_1789_out" "")"
_1789_fx review-comments "[$(_1789_rc 607 "cursor[bot]" "$_1789_H" "$_1789_H" "**High Severity** $_1789_bb_finding")]"
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
run_test "1789_T2.16_bugbot_neutral_path_bound_needs_fixes" "needs_fixes|1" \
  "$(kv_value_default RESULT "$_1789_out" "")|$(kv_value_default BLOCKING_COUNT "$_1789_out" "")"

# --- T2.16 Devin: Phase 1 (pre-trigger) findings and the Phase 3 collection.
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run completed '"success"')"
_1789_fx review-comments "[$(_1789_rc 611 "devin-ai-integration[bot]" "$_1789_H" "$_1789_OLD" "Bug: off-by-one in the loop bound")]"
_1789_out="$(_1789_run_gh run_devin_review 300 60)"
run_test "1789_T2.16_devin_drifted_comment_ignored_both_phases_clean" "clean||0" "$(_1789_rre "$_1789_out")"
_1789_fx review-comments "[$(_1789_rc 612 "devin-ai-integration[bot]" "$_1789_H" "$_1789_H" "Bug: off-by-one in the loop bound")]"
_1789_out="$(_1789_run_gh run_devin_review 300 60)"
run_test "1789_T2.16_devin_bound_comment_phase1_needs_fixes" "needs_fixes|existing_findings|1" "$(_1789_rre "$_1789_out")"
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run completed '"success"')"
_1789_fx review-comments@60 "[$(_1789_rc 613 "devin-ai-integration[bot]" "$_1789_H" "$_1789_H" "Bug: off-by-one in the loop bound")]"
_1789_out="$(_1789_run_gh run_devin_review 300 60)"
run_test "1789_T2.16_devin_bound_comment_phase3_needs_fixes" "needs_fixes||1" "$(_1789_rre "$_1789_out")"
# A Devin review bound to another revision is not a finding either.
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run completed '"success"')"
_1789_fx reviews "[{\"id\":9,\"user\":{\"login\":\"devin-ai-integration[bot]\"},\"state\":\"CHANGES_REQUESTED\",\"submitted_at\":\"2020-01-01T00:00:30Z\",\"commit_id\":\"$_1789_OLD\",\"body\":\"Fix the loop bound\"}]"
_1789_out="$(_1789_run_gh run_devin_review 300 60)"
run_test "1789_T2.16_devin_other_revision_review_not_a_finding" "clean||0" "$(_1789_rre "$_1789_out")"

# --- T2.16 CodeRabbit: Phase 1 (pre-trigger) findings and the Phase 3 collection.
_1789_cr_finding="🔴 Critical: unquoted expansion"
_1789_cr_ok_status='[{"id":9,"context":"CodeRabbit","state":"success","description":"Review completed","created_at":"2020-01-01T00:00:09Z"}]'
_1789_gh_reset
_1789_fx review-comments "[$(_1789_rc 621 "coderabbitai[bot]" "$_1789_H" "$_1789_OLD" "$_1789_cr_finding")]"
_1789_fx statuses "$_1789_cr_ok_status"
_1789_out="$(_1789_run_gh run_coderabbit_review 3)"
# The finding filters drop the drifted comment (no existing_findings from
# Phase 1, no Phase 3 finding); an unreplied older-head comment still blocks
# through the CodeRabbit thread gate, which reads threads regardless of
# revision (plan D15: unresolved threads are out of the binding).
run_test "1789_T2.16_coderabbit_drifted_comment_not_a_finding_thread_gate_blocks" "needs_fixes|coderabbit_unreplied_rest_comments|1" "$(_1789_rre "$_1789_out")"
_1789_out="$(_1789_handler_overrides="$_1789_handler_overrides
  check_unreplied_rest_comments() { printf '0\n'; }" _1789_run_gh run_coderabbit_review 3)"
run_test "1789_T2.16_coderabbit_drifted_comment_ignored_both_phases_clean" "clean|coderabbit_status_success_fallback|0" "$(_1789_rre "$_1789_out")"
_1789_fx review-comments "[$(_1789_rc 622 "coderabbitai[bot]" "$_1789_H" "$_1789_H" "$_1789_cr_finding")]"
_1789_out="$(_1789_run_gh run_coderabbit_review 3)"
run_test "1789_T2.16_coderabbit_bound_comment_phase1_needs_fixes" "needs_fixes|existing_findings|1" "$(_1789_rre "$_1789_out")"
_1789_gh_reset
_1789_fx statuses@1 "$_1789_cr_ok_status"
_1789_fx review-comments@1 "[$(_1789_rc 623 "coderabbitai[bot]" "$_1789_H" "$_1789_H" "$_1789_cr_finding")]"
_1789_out="$(_1789_run_gh run_coderabbit_review 3)"
run_test "1789_T2.16_coderabbit_bound_comment_phase3_needs_fixes" "needs_fixes||1" "$(_1789_rre "$_1789_out")"
_1789_gh_reset
_1789_fx statuses@1 "$_1789_cr_ok_status"
_1789_fx review-comments@1 "[$(_1789_rc 624 "coderabbitai[bot]" "$_1789_H" "$_1789_OLD" "$_1789_cr_finding")]"
_1789_out="$(_1789_handler_overrides="$_1789_handler_overrides
  check_unreplied_rest_comments() { printf '0\n'; }" _1789_run_gh run_coderabbit_review 3)"
run_test "1789_T2.16_coderabbit_drifted_comment_phase3_ignored" "clean|coderabbit_status_success_fallback|0" "$(_1789_rre "$_1789_out")"

# --- T2.17 completion signals.
# Devin: a summary review on H0 submitted after the committer time does not
# end the wait; the Devin check on H never completes → the D8 Devin row.
_1789_gh_reset
_1789_fx check-runs "$(_1789_dv_run in_progress null)"
_1789_fx reviews "[{\"id\":10,\"user\":{\"login\":\"devin-ai-integration[bot]\"},\"state\":\"COMMENTED\",\"submitted_at\":\"2020-01-01T00:00:30Z\",\"commit_id\":\"$_1789_OLD\",\"body\":\"No Issues Found\"}]"
_1789_out="$(_1789_run_gh run_devin_review 2)"
run_test "1789_T2.17_devin_other_revision_summary_does_not_end_wait" "waiting_on_reviewer|reviewer-no-verdict-yet|4|check_not_completed|2" \
  "$(_1789_rre "$_1789_out")|$(kv_value_default WAIT_EXPIRED_DETAIL "$_1789_out" "")|$(_1789_tick)"
# The same summary bound to H ends the wait at once (clean).
_1789_fx reviews "[{\"id\":10,\"user\":{\"login\":\"devin-ai-integration[bot]\"},\"state\":\"COMMENTED\",\"submitted_at\":\"2020-01-01T00:00:30Z\",\"commit_id\":\"$_1789_H\",\"body\":\"No Issues Found\"}]"
printf '0\n' > "$_1789_gh_dir/tick"
_1789_out="$(_1789_run_gh run_devin_review 2)"
run_test "1789_T2.17_devin_bound_summary_ends_wait" "clean||0|0" "$(_1789_rre "$_1789_out")|$(_1789_tick)"
# CodeRabbit: a review on H0 does not end the wait (no other activity → kept skip).
_1789_gh_reset
_1789_fx reviews "[{\"id\":11,\"user\":{\"login\":\"coderabbitai[bot]\"},\"state\":\"COMMENTED\",\"submitted_at\":\"2020-01-01T00:00:30Z\",\"commit_id\":\"$_1789_OLD\",\"body\":\"Summary\"}]"
_1789_out="$(_1789_run_gh run_coderabbit_review 3)"
run_test "1789_T2.17_coderabbit_other_revision_review_does_not_end_wait" "skipped|no_review|0|3" \
  "$(_1789_rre "$_1789_out")|$(_1789_tick)"
# A walkthrough comment edited after the committer time, with no H review and
# no status, records activity but keeps polling and expires as No verdict yet
# review_not_submitted (the CodeRabbit activity-seen expiry is now reachable).
_1789_gh_reset
_1789_fx issue-comments '[{"id":700,"user":{"login":"coderabbitai[bot]"},"created_at":"2019-12-31T00:00:00Z","updated_at":"2020-01-01T00:00:30Z","body":"<!-- walkthrough_start -->\n## Walkthrough\nThe change adds a guard."}]'
_1789_out="$(_1789_run_gh run_coderabbit_review 3)"
_1789_assert_waiting T2.17_coderabbit_walkthrough_only coderabbit "$_1789_out" review_not_submitted "$_1789_H"
run_test "1789_T2.17_coderabbit_walkthrough_keeps_polling_to_budget" "3" "$(_1789_tick)"
# A CodeRabbit success status on H ends the wait (clean after the thread gate).
_1789_gh_reset
_1789_fx statuses@1 "$_1789_cr_ok_status"
_1789_out="$(_1789_run_gh run_coderabbit_review 3)"
run_test "1789_T2.17_coderabbit_success_status_ends_wait" "clean|coderabbit_status_success_fallback|0|1" \
  "$(_1789_rre "$_1789_out")|$(_1789_tick)"
# A review bound to H also ends the wait at once.
_1789_gh_reset
_1789_fx reviews "[{\"id\":12,\"user\":{\"login\":\"coderabbitai[bot]\"},\"state\":\"COMMENTED\",\"submitted_at\":\"2020-01-01T00:00:30Z\",\"commit_id\":\"$_1789_H\",\"body\":\"Summary\"}]"
_1789_out="$(_1789_run_gh run_coderabbit_review 3)"
run_test "1789_T2.17_coderabbit_bound_review_ends_wait" "clean||0|0" "$(_1789_rre "$_1789_out")|$(_1789_tick)"
unset _1789_bb_finding _1789_cr_finding _1789_cr_ok_status

# ---------------------------------------------------------------------------
# Phase 3 — reviewer-failed label reconciliation (plan D9) and cross-platform
# precedence (plan D10): T3.1–T3.8. Platform outcomes are recorded through the
# real reviewer_loop_process_platform_output, then the post-loop functions run
# against the global mock gh (MOCK_GH_CALL_LOG records the label edits;
# MOCK_GH_OUTPUT is what `gh pr view --json labels` returns).
# ---------------------------------------------------------------------------
_1789_o() {
  # _1789_o <result> [reason]: a minimal platform output block.
  printf 'RESULT=%s\n' "$1"
  [ -n "${2:-}" ] && printf 'REASON=%s\n' "$2"
  printf 'COMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n'
}
_1789_rec_log="$_1789_dir/reconcile-calls.log"
# _1789_reconcile <label_present 0|1>: run the reconcile with the current
# aggregate and print "<adds>|<removes>|<status>".
_1789_reconcile() {
  local _st=0 _adds _removes _labels='some-other-label'
  : > "$_1789_rec_log"
  [ "$1" = "1" ] && _labels='reviewer-failed'
  (
    export MOCK_GH_CALL_LOG="$_1789_rec_log" MOCK_GH_OUTPUT="$_labels"
    unset MOCK_GH_EXIT MOCK_GH_PR_EDIT_EXIT MOCK_GH_LABEL_VIEW_EXIT MOCK_GH_LABEL_CREATE_EXIT
    reviewer_loop_reconcile_reviewer_failed_label "42" "$aggregate_result" "$aggregate_reason" 2>/dev/null
  ) || _st=$?
  _adds="$(grep -c -- 'pr edit 42 --add-label reviewer-failed' "$_1789_rec_log" || true)"
  _removes="$(grep -c -- 'pr edit 42 --remove-label reviewer-failed' "$_1789_rec_log" || true)"
  printf '%s|%s|%s\n' "$_adds" "$_removes" "$_st"
}

# T3.1 — the PR carries reviewer-failed; this run re-reviews and is clean →
# the label is removed (D9: required = per-platform evidence OR aggregate).
_1789_reset_processing_globals
reviewer_loop_process_platform_output "pr-agent" 1 "$(_1789_o clean)" 0 1 >/dev/null 2>&1
reviewer_loop_process_platform_output "bugbot" 2 "$(_1789_o clean)" 0 1 >/dev/null 2>&1
run_test "1789_T3.1_clean_rereview_removes_label" "0|1|0" "$(_1789_reconcile 1)"
run_test "1789_T3.1_clean_rereview_absent_label_noop" "0|0|0" "$(_1789_reconcile 0)"

# T3.2 — same, but every platform replayed from a clean ledger (#1692 staging):
# the replay output goes through reviewer_loop_process_platform_output exactly
# as the main loop's pre-dispatch replay does, and reconciliation removes the
# stale label.
_1789_reset_processing_globals
for _1789_p in local-ai-reviewer bugbot; do
  reviewer_loop_process_platform_output "$_1789_p" 1 "$(reviewer_loop_stage_skip_output "$loop_head_sha")" 0 1 >/dev/null 2>&1
done
run_test "1789_T3.2_replayed_aggregate_clean" "clean" "$aggregate_result"
run_test "1789_T3.2_replayed_no_failure_evidence" "0" "$reviewer_failed_required"
run_test "1789_T3.2_replayed_run_removes_label" "0|1|0" "$(_1789_reconcile 1)"
# The main loop's replay path is the one composed above: the pre-dispatch replay
# calls reviewer_loop_process_platform_output with the stage-skip output, and
# the loop's `replay` action continues to the post-loop path (no exit between).
run_test "1789_T3.2_replay_path_processes_output" "1" \
  "$(awk '/^reviewer_loop_platform_pre_dispatch\(\)/{f=1} f && /reviewer_loop_stage_skip_output "\$loop_head_sha"/{print 1; exit} f && /^}/{exit}' "$_1789_loop_src")"

# T3.3 — needs-fixes or waiting run with no failure evidence → the label is
# removed (when present) and never added.
_1789_reset_processing_globals
reviewer_loop_process_platform_output "pr-agent" 1 "$(_1789_o needs_fixes blocking)" 1 1 >/dev/null 2>&1
run_test "1789_T3.3_needs_fixes_removes_label" "0|1|0" "$(_1789_reconcile 1)"
run_test "1789_T3.3_needs_fixes_not_added" "0|0|0" "$(_1789_reconcile 0)"
_1789_reset_processing_globals
reviewer_loop_process_platform_output "bugbot" 1 "$(print_no_verdict_yet bugbot check_not_completed "$loop_head_sha" "")" 4 1 >/dev/null 2>&1
run_test "1789_T3.3_waiting_aggregate" "waiting_on_reviewer|reviewer-no-verdict-yet" "${aggregate_result}|${aggregate_reason}"
run_test "1789_T3.3_waiting_removes_label" "0|1|0" "$(_1789_reconcile 1)"
run_test "1789_T3.3_waiting_not_added" "0|0|0" "$(_1789_reconcile 0)"

# T3.4 — failure evidence anywhere in the run adds the label.
# (a) Mixed compare run: one failed platform plus one clean.
_1789_reset_processing_globals
compare_mode=1
reviewer_loop_process_platform_output "bugbot" 1 "$(_1789_o escalate bugbot-run-timed-out)" 2 1 >/dev/null 2>&1
reviewer_loop_process_platform_output "pr-agent" 2 "$(_1789_o clean)" 0 1 >/dev/null 2>&1
reviewer_loop_compare_restore_aggregate
run_test "1789_T3.4_compare_failed_plus_clean_aggregate" "escalate|bugbot-run-timed-out" "${aggregate_result}|${aggregate_reason}"
run_test "1789_T3.4_compare_failed_plus_clean_adds_label" "1|0|0" "$(_1789_reconcile 0)"
# (b) A needs-fixes run with a skipped/unavailable peer.
_1789_reset_processing_globals
reviewer_loop_process_platform_output "greptile" 1 "$(_1789_o skipped unavailable)" 0 1 >/dev/null 2>&1
reviewer_loop_process_platform_output "pr-agent" 2 "$(_1789_o needs_fixes blocking)" 1 1 >/dev/null 2>&1
run_test "1789_T3.4_needs_fixes_unavailable_peer_aggregate" "needs_fixes" "$aggregate_result"
run_test "1789_T3.4_needs_fixes_unavailable_peer_adds_label" "1|0|0" "$(_1789_reconcile 1)"
# (c) A clean run with a CodeRabbit CLI skipped/no_output peer (the T2.28
# composed path through the real companion) → label added.
_1789_reset_processing_globals
reviewer_loop_process_platform_output "coderabbit-cli" 1 "$(_1789_run_cr_cli 124 "" 30)" 0 1 >/dev/null 2>&1
reviewer_loop_process_platform_output "pr-agent" 2 "$(_1789_o clean)" 0 1 >/dev/null 2>&1
run_test "1789_T3.4_cli_no_output_peer_aggregate" "clean" "$aggregate_result"
run_test "1789_T3.4_cli_no_output_peer_adds_label" "1|0|0" "$(_1789_reconcile 0)"
# (d) The same clean run with the CodeRabbit CLI `timeout` kept skip instead →
# no failure evidence, so a present label is removed.
_1789_reset_processing_globals
reviewer_loop_process_platform_output "coderabbit-cli" 1 "$(_1789_run_cr_cli 0 4 1)" 0 1 >/dev/null 2>&1
reviewer_loop_process_platform_output "pr-agent" 2 "$(_1789_o clean)" 0 1 >/dev/null 2>&1
run_test "1789_T3.4_cli_kept_skip_peer_flag" "1" \
  "$(printf '%s\n' "${platform_blocking_outputs[0]#*$'\036'}" | awk -F= '/^NO_VERDICT_YET=/{print $2; exit}')"
run_test "1789_T3.4_cli_kept_skip_peer_removes_label" "0|1|0" "$(_1789_reconcile 1)"
# (e) The aggregate alone also requires it (a loop-level escalation with no
# failed platform, for example ledger_persist_failed after a clean round).
_1789_reset_processing_globals
reviewer_loop_process_platform_output "pr-agent" 1 "$(_1789_o clean)" 0 1 >/dev/null 2>&1
aggregate_result="escalate"; aggregate_reason="ledger_persist_failed"
run_test "1789_T3.4_aggregate_escalate_adds_label" "1|0|0" "$(_1789_reconcile 0)"
# ...and an availability escalate (rate_limited) neither adds nor keeps it.
aggregate_reason="rate_limited"
run_test "1789_T3.4_aggregate_rate_limited_removes_label" "0|1|0" "$(_1789_reconcile 1)"

# T3.5 — a failed add or remove prints the WARN and changes neither the
# function's status nor the aggregate.
_1789_reset_processing_globals
reviewer_loop_process_platform_output "pr-agent" 1 "$(_1789_o clean)" 0 1 >/dev/null 2>&1
_1789_err="$(export MOCK_GH_OUTPUT='reviewer-failed' MOCK_GH_PR_EDIT_EXIT=1; unset MOCK_GH_CALL_LOG MOCK_GH_EXIT; \
  reviewer_loop_reconcile_reviewer_failed_label "42" "$aggregate_result" "$aggregate_reason" 2>&1 >/dev/null)" && _1789_rc=0 || _1789_rc=$?
run_test "1789_T3.5_remove_failure_status" "0" "$_1789_rc"
run_test "1789_T3.5_remove_failure_warns" "1" \
  "$(printf '%s\n' "$_1789_err" | grep -c 'WARN: failed to remove reviewer-failed label from PR #42' || true)"
run_test "1789_T3.5_remove_failure_aggregate_unchanged" "clean" "$aggregate_result"
_1789_reset_processing_globals
reviewer_loop_process_platform_output "bugbot" 1 "$(_1789_o escalate fetch-failed)" 2 1 >/dev/null 2>&1
_1789_err="$(export MOCK_GH_OUTPUT='some-other-label' MOCK_GH_LABEL_VIEW_EXIT=0 MOCK_GH_PR_EDIT_EXIT=1; unset MOCK_GH_CALL_LOG MOCK_GH_EXIT; \
  reviewer_loop_reconcile_reviewer_failed_label "42" "$aggregate_result" "$aggregate_reason" 2>&1 >/dev/null)" && _1789_rc=0 || _1789_rc=$?
run_test "1789_T3.5_add_failure_status" "0" "$_1789_rc"
run_test "1789_T3.5_add_failure_warns" "1" \
  "$(printf '%s\n' "$_1789_err" | grep -c 'WARN: failed to apply reviewer-failed label to PR #42' || true)"
run_test "1789_T3.5_add_failure_aggregate_unchanged" "escalate|fetch-failed" "${aggregate_result}|${aggregate_reason}"

# T3.6 — source order: the main flow (after the harness return point) calls the
# reconcile function exactly once, after the platform loop and after the
# persistence step; the only other label syncs in the main flow are the
# release-guard and not-configured exits, both removal-only (`… 0`). Every
# pre-loop refusal exit (ownership, lock, truncated_run,
# execution_budget_misconfigured) therefore leaves the label unchanged.
_1789_ret_line="$(grep -n '_HARNESS_MODE_EFFECTIVE.*return 0' "$_1789_loop_src" | head -1 | cut -d: -f1)"
_1789_main_calls="$(awk -v start="$_1789_ret_line" 'NR > start && /^[^#]*reviewer_loop_reconcile_reviewer_failed_label "/ {print NR}' "$_1789_loop_src")"
run_test "1789_T3.6_reconcile_called_once_in_main_flow" "1" "$(printf '%s\n' "$_1789_main_calls" | grep -c . || true)"
_1789_loop_start="$(awk -v start="$_1789_ret_line" 'NR > start && /^for index in "\$\{!platforms\[@\]\}"; do/ {print NR; exit}' "$_1789_loop_src")"
_1789_persist_line="$(awk -v start="$_1789_ret_line" 'NR > start && /^  _post_review_summary "\$aggregate_result" "\$aggregate_reason"/ {print NR; exit}' "$_1789_loop_src")"
run_test "1789_T3.6_reconcile_after_loop_and_persistence" "yes" \
  "$( [ -n "$_1789_main_calls" ] && [ -n "$_1789_loop_start" ] && [ -n "$_1789_persist_line" ] \
      && [ "$_1789_main_calls" -gt "$_1789_loop_start" ] && [ "$_1789_main_calls" -gt "$_1789_persist_line" ] \
      && echo yes || echo no)"
run_test "1789_T3.6_main_flow_other_syncs_are_removal_only" "2|2" \
  "$(awk -v start="$_1789_ret_line" 'NR > start && /^[^#]*sync_reviewer_failed_label "/' "$_1789_loop_src" | grep -c . || true)|$(awk -v start="$_1789_ret_line" 'NR > start && /^[^#]*sync_reviewer_failed_label "\$pr_number" 0$/' "$_1789_loop_src" | grep -c . || true)"
run_test "1789_T3.6_no_label_sync_before_release_guard" "0" \
  "$(awk -v start="$_1789_ret_line" 'NR > start && /^# --- Release PR early-exit guard ---/{exit} NR > start && /^[^#]*(sync_reviewer_failed_label|reviewer_loop_reconcile_reviewer_failed_label) "/' "$_1789_loop_src" | grep -c . || true)"
run_test "1789_T3.6_reconcile_defined_before_harness_return" "yes" \
  "$(_1789_fn_line="$(grep -n '^reviewer_loop_reconcile_reviewer_failed_label()' "$_1789_loop_src" | cut -d: -f1)"; \
     [ -n "$_1789_fn_line" ] && [ "$_1789_fn_line" -lt "$_1789_ret_line" ] && echo yes || echo no)"
run_test "1789_T3.6_no_direct_aggregate_sync_left" "0" \
  "$(grep -c 'sync_reviewer_failed_label "\$pr_number" "\$reviewer_failed_required"' "$_1789_loop_src" || true)"

# T3.7 — precedence function (D10): failed + waiting → escalate; findings +
# waiting → needs_fixes; waiting + clean → waiting; kept skip + clean → clean;
# a tie → the earliest platform; an unrecognized result ranks with failures.
run_test "1789_T3.7_failed_beats_waiting" "1|devin|escalate|devin_run_failed" \
  "$(reviewer_loop_precedence_select "bugbot|waiting_on_reviewer|reviewer-no-verdict-yet" "devin|escalate|devin_run_failed")"
run_test "1789_T3.7_findings_beat_waiting" "2|pr-agent|needs_fixes|blocking" \
  "$(reviewer_loop_precedence_select "bugbot|waiting_on_reviewer|reviewer-no-verdict-yet" "pr-agent|needs_fixes|blocking")"
run_test "1789_T3.7_waiting_beats_clean" "3|bugbot|waiting_on_reviewer|reviewer-no-verdict-yet" \
  "$(reviewer_loop_precedence_select "pr-agent|clean|" "bugbot|waiting_on_reviewer|reviewer-no-verdict-yet")"
run_test "1789_T3.7_kept_skip_and_clean_is_clean" "4|devin|skipped|no_check_run" \
  "$(reviewer_loop_precedence_select "devin|skipped|no_check_run" "pr-agent|clean|")"
run_test "1789_T3.7_tie_goes_to_earliest" "2|greptile|needs_fixes|a" \
  "$(reviewer_loop_precedence_select "greptile|needs_fixes|a" "pr-agent|needs_rerun|" "bugbot|needs_fixes|b")"
run_test "1789_T3.7_failed_tie_earliest" "1|coderabbit|escalate|coderabbit_status_failed" \
  "$(reviewer_loop_precedence_select "pr-agent|clean|" "coderabbit|escalate|coderabbit_status_failed" "bugbot|escalate|fetch-failed")"
run_test "1789_T3.7_unrecognized_ranks_as_failure" "1|x|weird|" \
  "$(reviewer_loop_precedence_select "bugbot|needs_fixes|blocking" "x|weird|")"
run_test "1789_T3.7_ranks" "1 2 2 3 4 4 1" \
  "$(for _1789_r in escalate needs_fixes needs_rerun waiting_on_reviewer clean skipped bogus; do reviewer_loop_precedence_rank "$_1789_r"; done | tr '\n' ' ' | sed 's/ $//')"
run_test "1789_T3.7_empty_selects_nothing" "|1" \
  "$(_1789_s="$(reviewer_loop_precedence_select "" 2>/dev/null)" && _1789_x=0 || _1789_x=$?; printf '%s|%s' "$_1789_s" "$_1789_x")"
_1789_reset_processing_globals
platform_peer_evidence=("pr-agent|clean|" "bugbot|waiting_on_reviewer|reviewer-no-verdict-yet")
run_test "1789_T3.7_reads_peer_evidence_by_default" "3|bugbot|waiting_on_reviewer|reviewer-no-verdict-yet" \
  "$(reviewer_loop_precedence_select)"

# T3.8 — compare mode uses the precedence function, not "first blocking
# platform governs": waiting first, findings later → needs_fixes with the
# findings platform's output (the old rule returned the waiting platform).
_1789_reset_processing_globals
compare_mode=1
reviewer_loop_process_platform_output "bugbot" 1 "$(print_no_verdict_yet bugbot check_not_completed "$loop_head_sha" "")" 4 1 >/dev/null 2>&1
reviewer_loop_process_platform_output "pr-agent" 2 "$(printf 'RESULT=needs_fixes\nREASON=blocking\nREVIEW_COMMENT_ID=901\nCOMMENT_COUNT=1\nBLOCKING_COUNT=1\nSUGGESTION_COUNT=0\n')" 1 1 >/dev/null 2>&1
reviewer_loop_process_platform_output "greptile" 3 "$(_1789_o clean)" 0 1 >/dev/null 2>&1
run_test "1789_T3.8_first_blocking_was_waiting" "waiting_on_reviewer" "$compare_first_blocking_result"
reviewer_loop_compare_restore_aggregate
run_test "1789_T3.8_compare_findings_beat_earlier_waiting" "needs_fixes|blocking|1" "${aggregate_result}|${aggregate_reason}|${aggregate_status}"
run_test "1789_T3.8_compare_output_is_governing_platform" "901" "$(kv_value_default REVIEW_COMMENT_ID "$aggregate_output" "")"
# Failed after findings → escalate (rank 1), output of the failed platform.
_1789_reset_processing_globals
compare_mode=1
reviewer_loop_process_platform_output "pr-agent" 1 "$(_1789_o needs_fixes blocking)" 1 1 >/dev/null 2>&1
reviewer_loop_process_platform_output "devin" 2 "$(_1789_o escalate devin_run_failed)" 2 1 >/dev/null 2>&1
reviewer_loop_compare_restore_aggregate
run_test "1789_T3.8_compare_failed_beats_earlier_findings" "escalate|devin_run_failed|2" "${aggregate_result}|${aggregate_reason}|${aggregate_status}"
run_test "1789_T3.8_compare_failed_output" "devin_run_failed" "$(kv_value_default REASON "$aggregate_output" "")"
# Waiting plus clean in compare mode → waiting; kept skip plus clean → clean.
_1789_reset_processing_globals
compare_mode=1
reviewer_loop_process_platform_output "pr-agent" 1 "$(_1789_o clean)" 0 1 >/dev/null 2>&1
reviewer_loop_process_platform_output "bugbot" 2 "$(print_no_verdict_yet bugbot check_not_completed "$loop_head_sha" "")" 4 1 >/dev/null 2>&1
reviewer_loop_process_platform_output "greptile" 3 "$(_1789_o clean)" 0 1 >/dev/null 2>&1
run_test "1789_T3.8_compare_last_platform_overwrote" "clean" "$aggregate_result"
reviewer_loop_compare_restore_aggregate
run_test "1789_T3.8_compare_waiting_beats_clean" "waiting_on_reviewer|reviewer-no-verdict-yet|4" "${aggregate_result}|${aggregate_reason}|${aggregate_status}"
_1789_reset_processing_globals
compare_mode=1
reviewer_loop_process_platform_output "devin" 1 "$(printf 'RESULT=skipped\nREASON=no_check_run\nNO_VERDICT_YET=1\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')" 0 1 >/dev/null 2>&1
reviewer_loop_process_platform_output "pr-agent" 2 "$(_1789_o clean)" 0 1 >/dev/null 2>&1
reviewer_loop_compare_restore_aggregate
run_test "1789_T3.8_compare_kept_skip_and_clean_is_clean" "clean" "$aggregate_result"
# Not compare mode → the restore is a no-op (normal runs stop at the first
# non-clean outcome; BR 5 forbids changing when evaluation stops).
_1789_reset_processing_globals
aggregate_result="needs_fixes"; aggregate_reason="sentinel"
compare_first_blocking_result="escalate"
platform_peer_evidence=("x|escalate|boom")
reviewer_loop_compare_restore_aggregate
run_test "1789_T3.8_normal_mode_untouched" "needs_fixes|sentinel" "${aggregate_result}|${aggregate_reason}"
# Defensive fallback: a blocking outcome was seen but no rank 1-3 evidence
# remains → the first blocking outcome (fail closed, never clean).
_1789_reset_processing_globals
compare_mode=1
aggregate_result="clean"
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
compare_first_blocking_result="escalate"
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
compare_first_blocking_reason="r"
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
compare_first_blocking_output="$(_1789_o escalate r)"
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
compare_first_blocking_status=2
platform_peer_evidence=("pr-agent|clean|")
reviewer_loop_compare_restore_aggregate
run_test "1789_T3.8_defensive_fallback_first_blocking" "escalate|r|2" "${aggregate_result}|${aggregate_reason}|${aggregate_status}"
# Loop-level gate escalations recorded during the platform loop keep precedence
# over every platform row in compare mode (BR 5 / D10; cycle-6 finding).
# _1789_gate_cap_run <order> [compare_mode]: drive the real pre-dispatch
# function with the expensive gate returning deferral_cap, in a subshell, and
# print "<result>|<reason>|<status>|<label adds on required>|<rewait key present>".
_1789_gate_cap_run() {
  local _order="$1" _mode="${2:-1}"
  (
    _1789_reset_processing_globals
    compare_mode="$_mode"
    # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
    stage_skip_enabled=0
    # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
    pr_number=42
    is_expensive_reviewer_platform() { [ "$1" = "bugbot" ]; }
    expensive_reviewer_gate() {
      printf 'EXPENSIVE_GATE_PLATFORM=%s\nEXPENSIVE_GATE_RESULT=deferral_cap\nEXPENSIVE_GATE_REASON=cap\n' "$2"
      return 1
    }
    _w() { reviewer_loop_process_platform_output "local-ai-reviewer" 1 "$(print_no_verdict_yet local-ai-reviewer check_not_completed "$loop_head_sha" "")" 4 1 >/dev/null 2>&1; }
    if [ "$_order" = "waiting_first" ]; then
      _w
      reviewer_loop_platform_pre_dispatch "bugbot" 2 >/dev/null 2>&1
    elif [ "$_order" = "findings_first" ]; then
      reviewer_loop_process_platform_output "pr-agent" 1 "$(_1789_o needs_fixes blocking)" 1 1 >/dev/null 2>&1
      reviewer_loop_platform_pre_dispatch "bugbot" 2 >/dev/null 2>&1
    else
      # The gate breaks the loop, so nothing runs after it.
      reviewer_loop_platform_pre_dispatch "bugbot" 1 >/dev/null 2>&1
    fi
    reviewer_loop_compare_restore_aggregate
    printf '%s|%s|%s|%s\n' "$aggregate_result" "$aggregate_reason" "$aggregate_status" "$(kv_value_default RESULT "$aggregate_output" "")"
    reviewer_failed_label_required_for_result "$aggregate_result" "$aggregate_reason" && echo "label_required" || echo "label_not_required"
  )
}
run_test "1789_T3.9_gate_cap_after_waiting_stays_escalate" \
  "escalate|expensive_gate_deferral_cap|2|escalate" "$(_1789_gate_cap_run waiting_first | sed -n 1p)"
run_test "1789_T3.9_gate_cap_after_waiting_label_required" "label_required" \
  "$(_1789_gate_cap_run waiting_first | sed -n 2p)"
run_test "1789_T3.9_gate_cap_after_findings_stays_escalate" \
  "escalate|expensive_gate_deferral_cap|2|escalate" "$(_1789_gate_cap_run findings_first | sed -n 1p)"
run_test "1789_T3.9_gate_cap_after_findings_label_required" "label_required" \
  "$(_1789_gate_cap_run findings_first | sed -n 2p)"
# Guard: normal (non-compare) mode is unchanged by the restore (a no-op there).
run_test "1789_T3.9_normal_mode_gate_cap_escalates" \
  "escalate|expensive_gate_deferral_cap|2|escalate" "$(_1789_gate_cap_run gate_first 0 | sed -n 1p)"
# Another in-loop loop-level escalation (#1656 second pass local_pass_unavailable,
# ready_for_review_failed): simulated exactly as the loop records it.
for _1789_gr in local_pass_unavailable ready_for_review_failed; do
  _1789_reset_processing_globals
  compare_mode=1
  reviewer_loop_process_platform_output "bugbot" 1 "$(print_no_verdict_yet bugbot check_not_completed "$loop_head_sha" "")" 4 1 >/dev/null 2>&1
  aggregate_result="escalate"; aggregate_reason="$_1789_gr"; aggregate_status=2
  aggregate_output="$(_1789_o escalate "$_1789_gr")"
  reviewer_loop_gate_break_result="escalate"
  reviewer_loop_compare_restore_aggregate
  run_test "1789_T3.9_gate_${_1789_gr}_stays_escalate" "escalate|${_1789_gr}|2" "${aggregate_result}|${aggregate_reason}|${aggregate_status}"
done
# A gate needs_fixes deferral outranks No verdict yet but not a platform failure.
_1789_reset_processing_globals
compare_mode=1
reviewer_loop_process_platform_output "bugbot" 1 "$(print_no_verdict_yet bugbot check_not_completed "$loop_head_sha" "")" 4 1 >/dev/null 2>&1
aggregate_result="needs_fixes"; aggregate_reason="expensive_gate_deferred"; aggregate_status=1
reviewer_loop_gate_break_result="needs_fixes"
reviewer_loop_compare_restore_aggregate
run_test "1789_T3.9_gate_needs_fixes_beats_waiting" "needs_fixes|expensive_gate_deferred" "${aggregate_result}|${aggregate_reason}"
_1789_reset_processing_globals
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
compare_mode=1
reviewer_loop_process_platform_output "devin" 1 "$(_1789_o escalate devin_run_failed)" 2 1 >/dev/null 2>&1
aggregate_result="needs_fixes"; aggregate_reason="expensive_gate_deferred"; aggregate_status=1
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
reviewer_loop_gate_break_result="needs_fixes"
reviewer_loop_compare_restore_aggregate
run_test "1789_T3.9_platform_failed_beats_gate_needs_fixes" "escalate|devin_run_failed" "${aggregate_result}|${aggregate_reason}"
# Source: every gate break site records the gate outcome.
run_test "1789_T3.9_all_gate_break_sites_record_outcome" "5" \
  "$(grep -c '^ *reviewer_loop_gate_break_result="' "$_1789_loop_src")"
# Source: the main flow's compare block calls the restore function and no
# longer copies compare_first_blocking_* into the aggregate itself.
run_test "1789_T3.8_main_flow_uses_restore" "1" \
  "$(awk -v start="$_1789_ret_line" 'NR > start && /^  reviewer_loop_compare_restore_aggregate$/' "$_1789_loop_src" | grep -c . || true)"
run_test "1789_T3.8_main_flow_no_first_blocking_copy" "0" \
  "$(awk -v start="$_1789_ret_line" 'NR > start && /aggregate_output="\$compare_first_blocking_output"/' "$_1789_loop_src" | grep -c . || true)"
run_test "1789_T3.8_help_text_states_precedence" "1" \
  "$(grep -c 'run, the overall exit code and RESULT follow the cross-platform precedence:' "$_1789_loop_src" || true)"
run_test "1789_T3.8_precedence_helpers_before_harness_return" "yes" \
  "$(_1789_a="$(grep -n '^reviewer_loop_precedence_select()' "$_1789_loop_src" | cut -d: -f1)"; \
     _1789_b="$(grep -n '^reviewer_loop_compare_restore_aggregate()' "$_1789_loop_src" | cut -d: -f1)"; \
     [ -n "$_1789_a" ] && [ -n "$_1789_b" ] && [ "$_1789_a" -lt "$_1789_ret_line" ] && [ "$_1789_b" -lt "$_1789_ret_line" ] && echo yes || echo no)"
# ---------------------------------------------------------------------------
# Phase 4b — automatic re-wait and recorded-request adoption (plan D5, D11):
# the re-wait state, the recorded-request lookup (both matched by invocation
# head), the handlers' adoption rows, and NO_VERDICT_REWAIT (T2.12, T4.1–T4.4,
# T4.6, T4.9, the state half of T4.10). Ledger payloads are built directly so
# these rows do not depend on the D12 timing commit.
# ---------------------------------------------------------------------------
_1789_RUN="run-1789"
_1789_H1="$(printf '1789%036d' 0 | tr 0 f)"
# _1789_entry <run_id> <classification_head> <head_sha> <result> <reason> [platform_results_json]
_1789_entry() {
  jq -nc --arg run "$1" --arg ch "$2" --arg hs "$3" --arg r "$4" --arg why "$5" \
    --argjson pr "${6:-[]}" '
      {iteration: 1, run_id: $run, head_sha: $hs, result: $r, reason: $why, platform_results: $pr}
      | if $ch == "__missing__" then . else . + {classification_head: $ch} end'
}
# _1789_ledger <entry_json...>: a reviewer_loop_history.v1 payload.
_1789_ledger() {
  printf '%s\n' "$@" | jq -sc '{schema: "reviewer_loop_history.v1", entries: (. | to_entries | map(.value + {iteration: (.key + 1)}))}'
}
# _1789_req_rec <platform> <source> <ref> <requested_at>: a platform_results record.
_1789_req_rec() {
  jq -nc --arg p "$1" --arg s "$2" --arg ref "$3" --arg at "$4" \
    '{platform: $p, result: "no_verdict_yet", raw_result: "waiting_on_reviewer", raw_reason: "reviewer-no-verdict-yet", requested_at: $at, requested_at_source: $s, request_ref: $ref}'
}
_1789_state() { PR_REVIEW_LOOP_RUN_ID="${3-$_1789_RUN}" reviewer_loop_no_verdict_rewait_state "$1" "$2"; }
_1789_recorded() { PR_REVIEW_LOOP_RUN_ID="${4-$_1789_RUN}" reviewer_loop_rewait_recorded_request "$1" "$2" "$3"; }
_1789_wait_entry="$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet)"

# --- T4.1: re-wait state (D11)
run_test "1789_T4.1_no_prior_entry_fresh" "fresh" "$(_1789_state "$(_1789_ledger)" "$_1789_H")"
run_test "1789_T4.1_prior_waiting_same_run_head_rewait" "rewait" "$(_1789_state "$(_1789_ledger "$_1789_wait_entry")" "$_1789_H")"
run_test "1789_T4.1_other_head_fresh" "fresh" "$(_1789_state "$(_1789_ledger "$_1789_wait_entry")" "$_1789_H1")"
run_test "1789_T4.1_other_run_fresh" "fresh" "$(_1789_state "$(_1789_ledger "$(_1789_entry other-run "$_1789_H" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet)")" "$_1789_H")"
run_test "1789_T4.1_unset_run_id_untracked" "untracked" "$(_1789_state "$(_1789_ledger "$_1789_wait_entry")" "$_1789_H" "")"
run_test "1789_T4.1_unavailable_ledger_untracked" "untracked" \
  "$(_1789_state '{"schema":"reviewer_loop_history.v1","history_status":"unavailable","entries":[]}' "$_1789_H")"
run_test "1789_T4.1_unreadable_ledger_untracked" "untracked" "$(_1789_state 'not json' "$_1789_H")"
run_test "1789_T4.1_unknown_head_untracked" "untracked" "$(_1789_state "$(_1789_ledger "$_1789_wait_entry")" "")"
run_test "1789_T4.1_head_case_insensitive" "rewait" \
  "$(_1789_state "$(_1789_ledger "$_1789_wait_entry")" "$(printf '%s' "$_1789_H" | tr 'a-f' 'A-F')")"
for _1789_reason in codex-github-review-pending codex-github-reaction-without-review; do
  run_test "1789_T4.1_codex_reason_${_1789_reason}_rewait" "rewait" \
    "$(_1789_state "$(_1789_ledger "$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" waiting_on_reviewer "$_1789_reason")")" "$_1789_H")"
done
run_test "1789_T4.1_needs_fixes_entry_fresh" "fresh" \
  "$(_1789_state "$(_1789_ledger "$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" needs_fixes blocking)")" "$_1789_H")"
run_test "1789_T4.1_other_waiting_reason_fresh" "fresh" \
  "$(_1789_state "$(_1789_ledger "$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" waiting_on_reviewer something-else)")" "$_1789_H")"
# NO_VERDICT_REWAIT: available only for fresh + a persisted summary (status 0);
# a failing _post_review_summary in fresh state prints untracked, never available.
run_test "1789_T4.1_rewait_value_fresh_persisted" "available" "$(reviewer_loop_no_verdict_rewait_value fresh 0)"
run_test "1789_T4.1_rewait_value_fresh_persist_failed" "untracked" "$(reviewer_loop_no_verdict_rewait_value fresh 1)"
run_test "1789_T4.1_rewait_value_rewait" "used" "$(reviewer_loop_no_verdict_rewait_value rewait 0)"
run_test "1789_T4.1_rewait_value_untracked" "untracked" "$(reviewer_loop_no_verdict_rewait_value untracked 0)"
run_test "1789_T4.1_rewait_value_unknown_state" "untracked" "$(reviewer_loop_no_verdict_rewait_value bogus 0)"
# The main flow prints it only for a No verdict yet waiting result, from the
# summary-persistence status of this invocation.
run_test "1789_T4.1_main_flow_prints_from_persist_status" "1" \
  "$(awk -v start="$_1789_ret_line" 'NR > start && /print_kv NO_VERDICT_REWAIT "\$\(reviewer_loop_no_verdict_rewait_value "\$\{reviewer_loop_rewait_state:-untracked\}" "\$\{_post_summary_exit:-1\}"\)"/' "$_1789_loop_src" | grep -c . || true)"
run_test "1789_T4.1_rewait_print_after_persistence" "yes" \
  "$(_1789_pl="$(awk -v start="$_1789_ret_line" 'NR > start && /print_kv NO_VERDICT_REWAIT/ {print NR; exit}' "$_1789_loop_src")"; \
     [ -n "$_1789_pl" ] && [ "$_1789_pl" -gt "$_1789_persist_line" ] && echo yes || echo no)"
# The state is resolved once, in the main flow, after the loop head is read
# and before the platform loop; each dispatch prepares its recorded request.
run_test "1789_T4.1_resolve_called_once_before_loop" "yes" \
  "$(_1789_rl="$(awk -v start="$_1789_ret_line" 'NR > start && /^reviewer_loop_rewait_resolve "\$pr_number"$/ {print NR}' "$_1789_loop_src")"; \
     _1789_hl="$(awk -v start="$_1789_ret_line" 'NR > start && /^loop_head_sha=""$/ {print NR; exit}' "$_1789_loop_src")"; \
     [ "$(printf '%s\n' "$_1789_rl" | grep -c .)" = "1" ] && [ "$_1789_rl" -gt "$_1789_hl" ] && [ "$_1789_rl" -lt "$_1789_loop_start" ] && echo yes || echo no)"
run_test "1789_T4.1_prepare_before_both_dispatch_sites" "2" \
  "$(grep -c '^ *reviewer_loop_rewait_prepare_platform "' "$_1789_loop_src" || true)"

# --- T4.2: a re-wait (waiting) entry adds nothing to the cycle counts.
_1789_count_body() { printf '%s\n```json\n%s\n```\n' "$REVIEWER_LOOP_HISTORY_MARKER" "$1"; }
_1789_nf_entry="$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" needs_fixes blocking)"
run_test "1789_T4.2_waiting_entries_not_counted" \
  "$(reviewer_loop_history_entries_count "$(_1789_count_body "$(_1789_ledger "$_1789_nf_entry")")" "$_1789_RUN")" \
  "$(reviewer_loop_history_entries_count "$(_1789_count_body "$(_1789_ledger "$_1789_nf_entry" "$_1789_wait_entry" "$_1789_wait_entry")")" "$_1789_RUN")"

# --- T4.6: the recorded-request lookup (invocation head, run, waiting, source)
_1789_rec_bb="$(_1789_req_rec bugbot request 9300 2020-01-01T00:00:02Z)"
_1789_rw="$(_1789_ledger "$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet "[$_1789_rec_bb]")")"
run_test "1789_T4.6_match_prints_key_lines" "RECORDED_REQUEST_REF=9300|RECORDED_REQUESTED_AT=2020-01-01T00:00:02Z" \
  "$(_1789_recorded "$_1789_rw" "$_1789_H" bugbot | paste -sd '|' -)"
run_test "1789_T4.6_empty_ref_keeps_time" "RECORDED_REQUEST_REF=|RECORDED_REQUESTED_AT=2020-01-01T00:00:02Z" \
  "$(_1789_recorded "$(_1789_ledger "$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet "[$(_1789_req_rec bugbot request "" 2020-01-01T00:00:02Z)]")")" "$_1789_H" bugbot | paste -sd '|' -)"
run_test "1789_T4.6_empty_ref_read_by_kv_value" "|2020-01-01T00:00:02Z" \
  "$(_1789_k="$(_1789_recorded "$(_1789_ledger "$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet "[$(_1789_req_rec bugbot request "" 2020-01-01T00:00:02Z)]")")" "$_1789_H" bugbot)"; \
     printf '%s|%s' "$(kv_value RECORDED_REQUEST_REF "$_1789_k")" "$(kv_value RECORDED_REQUESTED_AT "$_1789_k")")"
run_test "1789_T4.6_other_head_nothing" "" "$(_1789_recorded "$_1789_rw" "$_1789_H1" bugbot)"
run_test "1789_T4.6_other_run_nothing" "" "$(_1789_recorded "$_1789_rw" "$_1789_H" bugbot other-run)"
run_test "1789_T4.6_unset_run_nothing" "" "$(_1789_recorded "$_1789_rw" "$_1789_H" bugbot "")"
run_test "1789_T4.6_wait_start_source_nothing" "" \
  "$(_1789_recorded "$(_1789_ledger "$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet "[$(_1789_req_rec bugbot wait_start "" 2020-01-01T00:00:02Z)]")")" "$_1789_H" bugbot)"
run_test "1789_T4.6_no_platform_record_nothing" "" "$(_1789_recorded "$_1789_rw" "$_1789_H" greptile)"
run_test "1789_T4.6_not_waiting_entry_nothing" "" \
  "$(_1789_recorded "$(_1789_ledger "$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" needs_fixes blocking "[$_1789_rec_bb]")")" "$_1789_H" bugbot)"
run_test "1789_T4.6_unavailable_ledger_nothing" "" \
  "$(_1789_recorded '{"schema":"reviewer_loop_history.v1","history_status":"unavailable","entries":[]}' "$_1789_H" bugbot)"
# The newest entry that makes the state rewait governs: an older entry's
# request is not used when the newest waiting entry lacks the platform.
run_test "1789_T4.6_newest_waiting_entry_governs" "" \
  "$(_1789_recorded "$(_1789_ledger "$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet "[$_1789_rec_bb]")" "$_1789_wait_entry")" "$_1789_H" bugbot)"
run_test "1789_T4.6_newest_record_in_entry_governs" "RECORDED_REQUEST_REF=9301" \
  "$(_1789_recorded "$(_1789_ledger "$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet "[$_1789_rec_bb,$(_1789_req_rec bugbot request 9301 2020-01-01T00:00:04Z)]")")" "$_1789_H" bugbot | head -1)"

# --- T4.10 (state half): a push between request posting and ledger
# persistence. The waiting entry was written with classification_head H0 (the
# invocation's loop head) and head_sha H1 (the head re-read at persistence).
# The next invocation on H1 is fresh, finds no recorded request for H1, and
# keeps H1's single re-wait unspent; the entry still counts for H0. An entry
# with no classification_head never matches, whatever its head_sha.
_1789_push_entry="$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H1" waiting_on_reviewer reviewer-no-verdict-yet "[$(_1789_req_rec greptile request 9001 2020-01-01T00:00:05Z)]")"
run_test "1789_T4.10_new_head_is_fresh" "fresh" "$(_1789_state "$(_1789_ledger "$_1789_push_entry")" "$_1789_H1")"
run_test "1789_T4.10_new_head_rewait_unspent" "available" \
  "$(reviewer_loop_no_verdict_rewait_value "$(_1789_state "$(_1789_ledger "$_1789_push_entry")" "$_1789_H1")" 0)"
run_test "1789_T4.10_no_recorded_request_for_new_head" "" "$(_1789_recorded "$(_1789_ledger "$_1789_push_entry")" "$_1789_H1" greptile)"
run_test "1789_T4.10_entry_counts_for_invocation_head" "rewait" "$(_1789_state "$(_1789_ledger "$_1789_push_entry")" "$_1789_H")"
run_test "1789_T4.10_missing_classification_head_never_matches" "fresh" \
  "$(_1789_state "$(_1789_ledger "$(_1789_entry "$_1789_RUN" __missing__ "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet)")" "$_1789_H")"
run_test "1789_T4.10_invalid_classification_head_never_matches" "fresh" \
  "$(_1789_state "$(_1789_ledger "$(_1789_entry "$_1789_RUN" "unknown-1-2-3" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet)")" "$_1789_H")"

# --- Handler adoption rows (D11 adoption table). _1789_rewait <ref> <at> sets
# re-wait mode with a recorded request; _1789_rewait_none sets re-wait mode
# with nothing recorded; _1789_rewait_off restores a fresh run.
_1789_rewait() {
  reviewer_loop_rewait_mode=1; reviewer_loop_recorded_request_found=1
  reviewer_loop_recorded_request_ref="$1"; reviewer_loop_recorded_requested_at="$2"
}
_1789_rewait_none() {
  reviewer_loop_rewait_mode=1; reviewer_loop_recorded_request_found=0
  reviewer_loop_recorded_request_ref=""; reviewer_loop_recorded_requested_at=""
}
_1789_rewait_off() {
  reviewer_loop_rewait_mode=0; reviewer_loop_recorded_request_found=0
  reviewer_loop_recorded_request_ref=""; reviewer_loop_recorded_requested_at=""
}
_1789_stderr_has() { grep -Fc -- "$1" "$_1789_gh_dir/stderr" || true; }
_1789_keys() {
  printf '%s|%s' "$(kv_value_default REVIEW_REQUESTED_AT "$1" "")" "$(kv_value_default REVIEW_REQUEST_REF "$1" "")"
}

# T2.12 — Bugbot re-wait with a recorded request: adopt it, post no comment
# (no trigger and no #1390 re-trigger), and print the recorded request
# unchanged (D12 carry-forward).
_1789_gh_reset
_1789_rewait 9300 2020-01-01T00:00:02Z
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
run_test "1789_T2.12_bugbot_rewait_posts_nothing" "0" "$(_1789_posts)"
run_test "1789_T2.12_bugbot_rewait_carries_request" "2020-01-01T00:00:02Z|9300" "$(_1789_keys "$_1789_out")"
run_test "1789_T2.12_bugbot_rewait_still_waiting" "waiting_on_reviewer|reviewer-no-verdict-yet|4" "$(_1789_rre "$_1789_out")"
run_test "1789_T2.12_bugbot_rewait_bounded_by_budget" "4" "$(_1789_tick)"
# A recorded run that completes on the head is the verdict, with no post.
_1789_gh_reset
_1789_fx check-runs@2 "$(printf '{"check_runs":[{"id":27,"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"success","started_at":"2020-01-01T00:00:03Z"}]}')"
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
run_test "1789_T2.12_bugbot_rewait_verdict_no_post" "clean||0|0" "$(_1789_rre "$_1789_out")|$(_1789_posts)"
# An empty recorded ref still adopts: no comment, the time carried forward.
_1789_gh_reset
_1789_rewait "" 2020-01-01T00:00:02Z
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
run_test "1789_T2.12_bugbot_rewait_empty_ref_posts_nothing" "0" "$(_1789_posts)"
run_test "1789_T2.12_bugbot_rewait_empty_ref_keys" "2020-01-01T00:00:02Z|" "$(_1789_keys "$_1789_out")"
# Re-wait with nothing recorded: post as fresh, log the D11 INFO line, but the
# #1390 re-trigger stays skipped (D3: skipped in re-wait mode).
_1789_gh_reset
_1789_rewait_none
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
run_test "1789_T2.12_bugbot_rewait_nothing_recorded_posts_once" "1" "$(_1789_posts)"
run_test "1789_T2.12_bugbot_rewait_nothing_recorded_info" "1" \
  "$(_1789_stderr_has "INFO: no recorded outstanding request for bugbot on $_1789_H; requesting a review")"
run_test "1789_T2.12_bugbot_fresh_post_records_request" "2020-01-01T00:00:05Z|9001" "$(_1789_keys "$_1789_out")"
_1789_rewait_off
# T4.6 — outside re-wait mode Bugbot posts its own trigger even when a
# `bugbot run` comment newer than the head commit time exists (no
# timestamp-based adoption).
_1789_gh_reset
_1789_fx issue-comments '[{"id":8800,"user":{"login":"runner"},"created_at":"2020-01-01T00:00:03Z","body":"bugbot run"}]'
# Budget 1: the D3 re-trigger point (1 s) is never reached inside the wait, so
# the only POST is the initial trigger.
_1789_out="$(_1789_run_gh run_bugbot_review 1)"
run_test "1789_T4.6_bugbot_fresh_posts_own_trigger" "1" "$(_1789_posts)"
run_test "1789_T4.6_bugbot_fresh_records_own_trigger" "2020-01-01T00:00:05Z|9001" "$(_1789_keys "$_1789_out")"

# T4.4 — Greptile re-wait reuses the recorded trigger comment (its reactions
# are readable), posts nothing, and carries the recorded request forward.
_1789_gh_reset
_1789_rewait 9100 2020-01-01T00:00:03Z
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T4.4_greptile_rewait_posts_nothing" "0" "$(_1789_posts)"
run_test "1789_T4.4_greptile_rewait_carries_request" "2020-01-01T00:00:03Z|9100" "$(_1789_keys "$_1789_out")"
run_test "1789_T4.4_greptile_rewait_polls_recorded_comment" "yes" \
  "$( [ "$(grep -c 'issues/comments/9100/reactions' "$_1789_gh_dir/calls.log")" -ge 2 ] && echo yes || echo no)"
run_test "1789_T4.4_greptile_rewait_waiting" "waiting_on_reviewer|reviewer-no-verdict-yet|4" "$(_1789_rre "$_1789_out")"
# A bot thumbs-up on the recorded comment is that request's answer.
_1789_gh_reset
_1789_fx reactions.9100 '[{"content":"+1","user":{"login":"greptile-apps[bot]"}}]'
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T4.4_greptile_rewait_answer_clean" "clean||0|0" "$(_1789_rre "$_1789_out")|$(_1789_posts)"
# An empty recorded ref → the D11 WARN, then one post as in a fresh run.
_1789_gh_reset
_1789_rewait "" 2020-01-01T00:00:03Z
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T4.4_greptile_empty_ref_posts_once" "1" "$(_1789_posts)"
run_test "1789_T4.4_greptile_empty_ref_warns" "1" \
  "$(_1789_stderr_has "WARN: recorded greptile request <empty> on $_1789_H is not readable; requesting a review")"
run_test "1789_T4.4_greptile_empty_ref_records_new_post" "2020-01-01T00:00:05Z|9001" "$(_1789_keys "$_1789_out")"
# A recorded comment whose reactions read fails (deleted, 404) → WARN, one post.
_1789_gh_reset
_1789_rewait 9100 2020-01-01T00:00:03Z
_1789_fx reactions-fail.9100 1
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T4.4_greptile_unreadable_posts_once" "1" "$(_1789_posts)"
run_test "1789_T4.4_greptile_unreadable_warns" "1" \
  "$(_1789_stderr_has "WARN: recorded greptile request 9100 on $_1789_H is not readable; requesting a review")"
# Re-wait with nothing recorded → the D11 INFO line, one post.
_1789_gh_reset
_1789_rewait_none
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T4.4_greptile_nothing_recorded_posts_once" "1" "$(_1789_posts)"
run_test "1789_T4.4_greptile_nothing_recorded_info" "1" \
  "$(_1789_stderr_has "INFO: no recorded outstanding request for greptile on $_1789_H; requesting a review")"
_1789_rewait_off

# T4.4 — PR-Agent re-wait treats the recorded request as pending: no /review,
# the recorded request carried forward; an empty ref still adopts.
_1789_gh_reset
_1789_rewait 9200 2020-01-01T00:00:04Z
_1789_out="$(_1789_run_gh run_pr_agent_review 3)"
run_test "1789_T4.4_pr_agent_rewait_posts_nothing" "0" "$(_1789_posts)"
run_test "1789_T4.4_pr_agent_rewait_carries_request" "2020-01-01T00:00:04Z|9200" "$(_1789_keys "$_1789_out")"
run_test "1789_T4.4_pr_agent_rewait_skip_reason" "recorded_request_adopted" "$(kv_value_default PR_AGENT_TRIGGER_SKIPPED "$_1789_out" "")"
_1789_gh_reset
_1789_rewait "" 2020-01-01T00:00:04Z
_1789_out="$(_1789_run_gh run_pr_agent_review 3)"
run_test "1789_T4.4_pr_agent_empty_ref_posts_nothing" "0" "$(_1789_posts)"
run_test "1789_T4.4_pr_agent_empty_ref_keys" "2020-01-01T00:00:04Z|" "$(_1789_keys "$_1789_out")"
_1789_gh_reset
_1789_rewait_none
_1789_out="$(_1789_run_gh run_pr_agent_review 3)"
run_test "1789_T4.4_pr_agent_nothing_recorded_posts_once" "1" "$(_1789_posts)"
run_test "1789_T4.4_pr_agent_nothing_recorded_info" "1" \
  "$(_1789_stderr_has "INFO: no recorded outstanding request for pr-agent on $_1789_H; requesting a review")"
run_test "1789_T4.4_pr_agent_fresh_post_records_request" "2020-01-01T00:00:05Z|9001" "$(_1789_keys "$_1789_out")"
_1789_rewait_off

# T4.9 — PR-Agent failed run in re-wait mode (D8 path (2) through adoption):
# an adopted request is outstanding, so no poll returns before the budget,
# and the failure-type newest run on H gives pr_agent_run_failed at the budget.
_1789_gh_reset
_1789_rewait 9200 2020-01-01T00:00:04Z
_1789_fx check-runs "$(_1789_pra_runs "$(_1789_pra 10 completed '"timed_out"' 10)")"
_1789_out="$(_1789_run_gh run_pr_agent_review 5)"
run_test "1789_T4.9_pre_failed_run_failed_at_budget" "escalate|pr_agent_run_failed|2" "$(_1789_rre "$_1789_out")"
run_test "1789_T4.9_pre_failed_waits_full_budget" "5" "$(_1789_tick)"
run_test "1789_T4.9_pre_failed_posts_nothing" "0" "$(_1789_posts)"
# Adopted while a run on H is active at the pending check, which then
# completes cancelled: still outstanding, so failure only at the budget.
_1789_gh_reset
_1789_fx check-runs "$(_1789_pra_runs "$(_1789_pra 10 in_progress null 10)")"
_1789_fx check-runs@1 "$(_1789_pra_runs "$(_1789_pra 10 completed '"cancelled"' 10)")"
_1789_out="$(_1789_run_gh run_pr_agent_review 5)"
run_test "1789_T4.9_active_then_cancelled_failed_at_budget" "escalate|pr_agent_run_failed|2" "$(_1789_rre "$_1789_out")"
run_test "1789_T4.9_active_then_cancelled_waits_full_budget" "5" "$(_1789_tick)"
run_test "1789_T4.9_active_then_cancelled_posts_nothing" "0" "$(_1789_posts)"
_1789_rewait_off

# T4.4 — CodeRabbit: in re-wait mode with a recorded request the conditional
# `@coderabbitai review` re-trigger is not posted; a fresh run posts it.
_1789_cr_no_trigger_timeout=1
_1789_gh_reset
_1789_out="$(_1789_run_gh run_coderabbit_review 3)"
run_test "1789_T4.4_coderabbit_fresh_posts_conditional_retrigger" "yes" \
  "$( [ "$(grep -c 'pr comment 42 --body @coderabbitai review' "$_1789_gh_dir/posts.log")" -ge 1 ] && echo yes || echo no)"
run_test "1789_T4.4_coderabbit_fresh_records_request" "yes" \
  "$( [ -n "$(kv_value_default REVIEW_REQUESTED_AT "$_1789_out" "")" ] && echo yes || echo no)"
_1789_gh_reset
_1789_rewait "" 2020-01-01T00:00:04Z
_1789_out="$(_1789_run_gh run_coderabbit_review 3)"
run_test "1789_T4.4_coderabbit_rewait_no_retrigger" "0" "$(_1789_posts)"
run_test "1789_T4.4_coderabbit_rewait_carries_request" "2020-01-01T00:00:04Z|" "$(_1789_keys "$_1789_out")"
_1789_rewait_off
unset _1789_cr_no_trigger_timeout

# T4.10 (handler half): the H1 invocation is fresh (no recorded request for
# H1), so Greptile posts its own trigger; a bot thumbs-up on the H0-era trigger
# R0 neither ends H1's wait nor gives a clean verdict.
_1789_gh_reset
_1789_fx reactions.8700 '[{"content":"+1","user":{"login":"greptile-apps[bot]"}}]'
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T4.10_greptile_posts_new_trigger" "1" "$(_1789_posts)"
run_test "1789_T4.10_old_trigger_thumbs_up_not_verdict" "waiting_on_reviewer|reviewer-no-verdict-yet|4" "$(_1789_rre "$_1789_out")"
run_test "1789_T4.10_old_trigger_never_polled" "0" "$(grep -c 'issues/comments/8700/reactions' "$_1789_gh_dir/calls.log" || true)"

# T4.3 — Codex in re-wait mode receives --max-retriggers 0; a fresh run keeps
# its configured value. The companion's REVIEW_REQUESTED_AT is forwarded.
_1789_codex_args="$_1789_dir/codex-args.log"
cat > "$_1789_stub_root/scripts/development-workflow/codex-github-reviewer.sh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$_1789_codex_args"
printf 'VERDICT: APPROVED\nREVIEW_REQUESTED_AT=2020-01-01T00:00:06Z\nREVIEWED_HEAD=1789aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
exit 0
STUB
chmod +x "$_1789_stub_root/scripts/development-workflow/codex-github-reviewer.sh"
_1789_handler_overrides_saved="$_1789_handler_overrides"
_1789_handler_overrides="${_1789_handler_overrides}
  codex_review_thread_evidence_counts() { printf '0\t0\t0\n'; }
"
_1789_rewait_none
_1789_out="$(_1789_run_handler run_codex_github_review 30)"
run_test "1789_T4.3_codex_rewait_max_retriggers_0" "1" "$(grep -c -- '--max-retriggers 0' "$_1789_codex_args" || true)"
run_test "1789_T4.3_codex_forwards_requested_at" "2020-01-01T00:00:06Z" "$(kv_value_default REVIEW_REQUESTED_AT "$_1789_out" "")"
_1789_rewait_off
_1789_out="$(_1789_run_handler run_codex_github_review 30)"
run_test "1789_T4.3_codex_fresh_keeps_max_retriggers" "1" "$(grep -c -- '--max-retriggers 1' "$_1789_codex_args" || true)"
_1789_handler_overrides="$_1789_handler_overrides_saved"
unset _1789_handler_overrides_saved _1789_codex_args

_1789_rewait_off

# ---------------------------------------------------------------------------
# Phase 4b — timing, ledger, summary, and waiting keys (plan D12): T5.1–T5.5,
# T4.7, and the D12 carry-forward half of T2.12. Wait start/end epochs are
# pinned after reviewer_loop_timing_begin/_end so seconds are deterministic.
# ---------------------------------------------------------------------------
_1789_T0=1577836800   # 2020-01-01T00:00:00Z
_1789_kv_file="$_1789_dir/kv.out"
# _1789_timed <platform> <index> <status> <budget> <source> <adjustment> <seconds> <output>:
# processes one output with a timing context whose wait started at T0 and
# ended <seconds> later; the printed keys land in $_1789_kv_file.
_1789_timed() {
  reviewer_loop_timing_begin "$4" "$5" "$6"
  reviewer_loop_timing_end
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  reviewer_loop_timing_start_epoch="$_1789_T0"
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  reviewer_loop_timing_end_epoch="$((_1789_T0 + $7))"
  reviewer_loop_process_platform_output "$1" "$2" "$8" "$3" 1 > "$_1789_kv_file" 2>/dev/null
}
_1789_kv() { kv_value_default "$1" "$(cat "$_1789_kv_file")" ""; }
_1789_has_key() { grep -c "^$1=" "$_1789_kv_file" || true; }
_1789_last_record() { printf '%s\n' "${platform_result_records[@]}" | jq -sc 'last'; }

# --- T5.1: timing keys
# A verdict on a request the handler posted → latency from the request time.
_1789_reset_processing_globals
_1789_timed bugbot 1 0 2400 default none 316 \
  "$(printf 'RESULT=clean\nREVIEW_REQUESTED_AT=2020-01-01T00:00:00Z\nREVIEW_REQUEST_REF=9001\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')"
run_test "1789_T5.1_verdict_keys" "verdict_received|2400|default|none|2020-01-01T00:00:00Z|request|9001|316" \
  "$(_1789_kv PLATFORM_1_OUTCOME_CLASS)|$(_1789_kv PLATFORM_1_WAIT_BUDGET_SECONDS)|$(_1789_kv PLATFORM_1_WAIT_BUDGET_SOURCE)|$(_1789_kv PLATFORM_1_WAIT_BUDGET_ADJUSTMENT)|$(_1789_kv PLATFORM_1_REQUESTED_AT)|$(_1789_kv PLATFORM_1_REQUESTED_AT_SOURCE)|$(_1789_kv PLATFORM_1_REQUEST_REF)|$(_1789_kv PLATFORM_1_LATENCY_SECONDS)"
run_test "1789_T5.1_verdict_no_waited_or_elapsed" "0|0" "$(_1789_has_key PLATFORM_1_WAITED_SECONDS)|$(_1789_has_key PLATFORM_1_ELAPSED_SECONDS)"
_1789_rec_verdict="$(_1789_last_record)"
# No verdict yet with no request printed → the wait start, waited seconds, no ref.
_1789_timed greptile 2 4 1200 configured large_diff 1200 "$(print_no_verdict_yet greptile no_acknowledgement "$_1789_H" "")"
run_test "1789_T5.1_no_verdict_keys" "no_verdict_yet|1200|configured|large_diff|2020-01-01T00:00:00Z|wait_start|1200" \
  "$(_1789_kv PLATFORM_2_OUTCOME_CLASS)|$(_1789_kv PLATFORM_2_WAIT_BUDGET_SECONDS)|$(_1789_kv PLATFORM_2_WAIT_BUDGET_SOURCE)|$(_1789_kv PLATFORM_2_WAIT_BUDGET_ADJUSTMENT)|$(_1789_kv PLATFORM_2_REQUESTED_AT)|$(_1789_kv PLATFORM_2_REQUESTED_AT_SOURCE)|$(_1789_kv PLATFORM_2_WAITED_SECONDS)"
run_test "1789_T5.1_no_request_ref_without_handler_ref" "0|0" "$(_1789_has_key PLATFORM_2_REQUEST_REF)|$(_1789_has_key PLATFORM_2_LATENCY_SECONDS)"
_1789_rec_waiting="$(_1789_last_record)"
# A failure-evidence skip → elapsed; a failure → latency.
_1789_reset_processing_globals
_1789_timed coderabbit-cli 1 0 1200 default none 40 "$(_1789_o skipped no_output)"
run_test "1789_T5.1_skip_keys" "skipped_failure_evidence|40|0" \
  "$(_1789_kv PLATFORM_1_OUTCOME_CLASS)|$(_1789_kv PLATFORM_1_ELAPSED_SECONDS)|$(_1789_has_key PLATFORM_1_LATENCY_SECONDS)"
_1789_timed bugbot 2 2 2400 default none 75 "$(_1789_o escalate bugbot-run-timed-out)"
run_test "1789_T5.1_failure_keys" "reviewer_failed|75" "$(_1789_kv PLATFORM_2_OUTCOME_CLASS)|$(_1789_kv PLATFORM_2_LATENCY_SECONDS)"
_1789_timed devin 3 0 1200 default none 9 "$(printf 'RESULT=skipped\nREASON=no_check_run\nNO_VERDICT_YET=1\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')"
run_test "1789_T5.1_kept_skip_waited" "no_verdict_yet|9" "$(_1789_kv PLATFORM_3_OUTCOME_CLASS)|$(_1789_kv PLATFORM_3_WAITED_SECONDS)"
# An unparsable REVIEW_REQUESTED_AT is not trusted → the wait start.
_1789_timed copilot 4 4 1200 default none 5 "$(printf 'RESULT=waiting_on_reviewer\nREASON=reviewer-no-verdict-yet\nREVIEW_REQUESTED_AT=yesterday\n')"
run_test "1789_T5.1_unparsable_request_time_is_wait_start" "wait_start|2020-01-01T00:00:00Z|5" \
  "$(_1789_kv PLATFORM_4_REQUESTED_AT_SOURCE)|$(_1789_kv PLATFORM_4_REQUESTED_AT)|$(_1789_kv PLATFORM_4_WAITED_SECONDS)"
# A #1692 replay → VERDICT_REUSED=1 and no budget, requested-at, or seconds key.
_1789_reset_processing_globals
reviewer_loop_process_platform_output pr-agent 1 "$(reviewer_loop_stage_skip_output "$loop_head_sha")" 0 1 > "$_1789_kv_file" 2>/dev/null
run_test "1789_T5.1_replay_reused" "1|verdict_received" "$(_1789_kv PLATFORM_1_VERDICT_REUSED)|$(_1789_kv PLATFORM_1_OUTCOME_CLASS)"
run_test "1789_T5.1_replay_no_timing_keys" "0" \
  "$(grep -c '^PLATFORM_1_\(WAIT_BUDGET_SECONDS\|REQUESTED_AT\|LATENCY_SECONDS\|WAITED_SECONDS\|ELAPSED_SECONDS\)=' "$_1789_kv_file" || true)"
_1789_rec_replay="$(_1789_last_record)"
run_test "1789_T5.1_replay_record" "true|verdict_received|false" \
  "$(printf '%s' "$_1789_rec_replay" | jq -r '[.reused, .outcome_class, has("requested_at")] | map(tostring) | join("|")')"
# Without a timing context (a call outside a dispatch) nothing is added.
_1789_reset_processing_globals
reviewer_loop_process_platform_output pr-agent 1 "$(_1789_o clean)" 0 1 > "$_1789_kv_file" 2>/dev/null
run_test "1789_T5.1_no_context_no_keys" "0|false" \
  "$(_1789_has_key PLATFORM_1_OUTCOME_CLASS)|$(_1789_last_record | jq -r 'has("outcome_class")')"
# Both dispatch sites take the wait start immediately before run_platform_review
# and the end immediately after.
run_test "1789_T5.1_timing_around_both_dispatch_sites" "2|2" \
  "$(grep -c '^ *reviewer_loop_timing_begin "' "$_1789_loop_src" || true)|$(grep -c '^ *reviewer_loop_timing_end$' "$_1789_loop_src" || true)"
run_test "1789_T5.1_begin_immediately_before_dispatch" "2" \
  "$(awk '/^ *reviewer_loop_timing_begin "/{b=NR} /run_platform_review "/ && b && NR - b <= 3 {c++; b=0} END{print c+0}' "$_1789_loop_src")"

# --- T5.3: ledger platform_results[] additive fields; existing readers still pass.
run_test "1789_T5.3_record_additive_fields" "clean|verdict_received|2400|default|none|2020-01-01T00:00:00Z|request|9001|316|latency|false" \
  "$(printf '%s' "$_1789_rec_verdict" | jq -r '[.result, .outcome_class, .wait_budget_seconds, .wait_budget_source, .wait_budget_adjustment, .requested_at, .requested_at_source, .request_ref, .elapsed_seconds, .elapsed_kind, .reused] | map(tostring) | join("|")')"
run_test "1789_T5.3_request_ref_only_when_printed" "false|waited" \
  "$(printf '%s' "$_1789_rec_waiting" | jq -r '[has("request_ref"), .elapsed_kind] | map(tostring) | join("|")')"
run_test "1789_T5.3_record_keeps_existing_keys" "bugbot|clean|clean|" \
  "$(printf '%s' "$_1789_rec_verdict" | jq -r '[.platform, .result, .raw_result, .raw_reason] | join("|")')"
_1789_t53_payload="$(jq -nc --argjson rec "$_1789_rec_verdict" --arg h "$_1789_H" \
  '{schema: "reviewer_loop_history.v1", entries: [{iteration: 1, platform_results: [$rec], reviewed_heads: [{platform: "bugbot", reviewed_head: $h}]}]}')"
run_test "1789_T5.3_clean_for_head_reader_unchanged" "clean_current" \
  "$(reviewer_loop_platform_clean_for_head "$_1789_t53_payload" bugbot "$_1789_H")"
run_test "1789_T5.3_extra_arg_must_be_object" '{"platform":"p","result":"clean","raw_result":"clean","raw_reason":""}' \
  "$(reviewer_loop_platform_result_record_json p clean "" 0 '[1]')"

# --- T2.12 (D12 carry-forward): the Bugbot re-wait adoption output, recorded
# through the loop, writes the recorded request unchanged, so a third
# invocation with the same run id and head adopts the same comment.
_1789_reset_processing_globals
loop_head_sha="$_1789_H"
_1789_timed bugbot 1 4 2400 default none 2400 \
  "$(printf 'REVIEW_REQUESTED_AT=2020-01-01T00:00:02Z\nREVIEW_REQUEST_REF=9300\n'; print_no_verdict_yet bugbot check_not_started "$_1789_H" "")"
_1789_t212_payload="$(_1789_ledger "$(_1789_entry "$_1789_RUN" "$_1789_H" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet "[$(_1789_last_record)]")")"
run_test "1789_T2.12_carry_forward_third_invocation_adopts_same" "RECORDED_REQUEST_REF=9300|RECORDED_REQUESTED_AT=2020-01-01T00:00:02Z" \
  "$(_1789_recorded "$_1789_t212_payload" "$_1789_H" bugbot | paste -sd '|' -)"

# --- T5.2: the summary's Reviewer timing section and the result line.
_1789_reset_processing_globals
_1789_timed bugbot 1 0 2400 default none 316 \
  "$(printf 'RESULT=clean\nREVIEW_REQUESTED_AT=2020-01-01T00:00:00Z\nREVIEW_REQUEST_REF=9001\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')"
_1789_timed greptile 2 4 1200 configured large_diff 1200 "$(print_no_verdict_yet greptile no_acknowledgement "$_1789_H" "")"
reviewer_loop_process_platform_output pr-agent 3 "$(reviewer_loop_stage_skip_output "$loop_head_sha")" 0 1 >/dev/null 2>&1
_1789_section="$(reviewer_loop_timing_summary_section)"
run_test "1789_T5.2_section_heading" "1" "$(printf '%s\n' "$_1789_section" | grep -c '^\*\*Reviewer timing:\*\*$' || true)"
run_test "1789_T5.2_verdict_line" "1" \
  "$(printf '%s\n' "$_1789_section" | grep -Fxc -- '- bugbot: verdict received (clean) — budget 2400s (built-in default); requested 2020-01-01T00:00:00Z; latency 316s' || true)"
run_test "1789_T5.2_no_verdict_line" "1" \
  "$(printf '%s\n' "$_1789_section" | grep -Fxc -- '- greptile: no verdict yet — budget 1200s (configured, large diff); requested 2020-01-01T00:00:00Z (wait start); waited 1200s' || true)"
run_test "1789_T5.2_reused_line" "1" \
  "$(printf '%s\n' "$_1789_section" | grep -Fxc -- '- pr-agent: verdict reused from an earlier run on this revision' || true)"
run_test "1789_T5.2_latency_note_once" "1" "$(printf '%s\n' "$_1789_section" | grep -c '^_Latency is measured to the poll that observed the verdict' || true)"
run_test "1789_T5.2_lines_at_most_200_chars" "0" \
  "$(printf '%s\n' "$_1789_section" | jq -Rr 'select(length > 200)' | grep -c . || true)"
_1789_reset_processing_globals
_1789_timed devin 1 2 1200 default none 3 "$(_1789_o escalate "$(printf 'x%.0s' $(seq 1 260))")"
run_test "1789_T5.2_long_line_capped" "200" \
  "$(reviewer_loop_timing_summary_section | grep '^- devin:' | jq -Rr 'length')"
_1789_reset_processing_globals
run_test "1789_T5.2_empty_without_records" "" "$(reviewer_loop_timing_summary_section)"
run_test "1789_T5.2_summary_uses_section_and_line" "1|1" \
  "$(grep -c '^  reviewer_timing_section="\$(reviewer_loop_timing_summary_section)"$' "$_1789_loop_src" || true)|$(grep -c 'result_line="\$(reviewer_loop_no_verdict_result_line "\$reason")"' "$_1789_loop_src" || true)"
run_test "1789_T5.2_section_in_comment_body" "1" \
  "$(grep -c '\${head_evidence_section}\${reviewer_timing_section}' "$_1789_loop_src" || true)"

# --- T5.4: a waiting aggregate with no failure-evidence peer.
_1789_reset_processing_globals
loop_head_sha="$_1789_H"
_1789_timed pr-agent 1 0 1200 default none 50 "$(_1789_o clean)"
_1789_timed bugbot 2 4 2400 default none 2400 \
  "$(printf 'REVIEW_REQUESTED_AT=2020-01-01T00:00:00Z\nREVIEW_REQUEST_REF=9001\n'; print_no_verdict_yet bugbot check_not_completed "$_1789_H" "")"
_1789_wk="$(reviewer_loop_emit_waiting_keys)"
run_test "1789_T5.4_waiting_keys" "bugbot|${_1789_H}|2020-01-01T00:00:00Z|2400|1" \
  "$(kv_value PENDING_REVIEWER "$_1789_wk")|$(kv_value PENDING_REVIEW_HEAD_SHA "$_1789_wk")|$(kv_value PENDING_REVIEW_REQUESTED_AT "$_1789_wk")|$(kv_value PENDING_REVIEW_WAITED_SECONDS "$_1789_wk")|$(kv_value NO_FAILURE_DETECTED "$_1789_wk")"
run_test "1789_T5.4_no_failed_peer_key" "0" "$(printf '%s\n' "$_1789_wk" | grep -c '^FAILED_PEER_PLATFORMS=' || true)"
run_test "1789_T5.4_result_line" "waiting_on_reviewer (reviewer-no-verdict-yet) — bugbot has not returned a verdict for ${_1789_H} after 2400s (budget 2400s, default); no reviewer failure was detected" \
  "$(reviewer_loop_no_verdict_result_line reviewer-no-verdict-yet)"
run_test "1789_T5.4_main_flow_emits_in_rewait_block" "yes" \
  "$(awk -v start="$_1789_ret_line" 'NR > start && /print_kv NO_VERDICT_REWAIT/ {f=1} f && /^  reviewer_loop_emit_waiting_keys$/ {print "yes"; exit} f && /^fi$/ {print "no"; exit}' "$_1789_loop_src")"

# --- T5.5: regression — a failure-evidence skip before a waiting platform.
# The real CodeRabbit CLI companion exits immediately with empty stdout
# (skipped/no_output), then Bugbot never completes.
_1789_reset_processing_globals
loop_head_sha="$_1789_H"
_1789_timed coderabbit-cli 1 0 1200 default none 2 "$(_1789_run_cr_cli 124 "" 30)"
_1789_timed bugbot 2 4 2400 default none 2400 "$(print_no_verdict_yet bugbot check_not_completed "$_1789_H" "")"
run_test "1789_T5.5_aggregate_waiting" "waiting_on_reviewer|reviewer-no-verdict-yet" "${aggregate_result}|${aggregate_reason}"
_1789_wk="$(reviewer_loop_emit_waiting_keys)"
run_test "1789_T5.5_pending_bugbot_failure_detected" "bugbot|0|coderabbit-cli" \
  "$(kv_value PENDING_REVIEWER "$_1789_wk")|$(kv_value NO_FAILURE_DETECTED "$_1789_wk")|$(kv_value FAILED_PEER_PLATFORMS "$_1789_wk")"
run_test "1789_T5.5_failed_peer_pairs" "coderabbit-cli|no_output" "$(reviewer_loop_failed_peer_platforms)"
run_test "1789_T5.5_label_added" "1|0|0" "$(_1789_reconcile 0)"
run_test "1789_T5.5_rewait_still_available" "available" "$(reviewer_loop_no_verdict_rewait_value fresh 0)"
_1789_line="$(reviewer_loop_no_verdict_result_line reviewer-no-verdict-yet)"
run_test "1789_T5.5_result_line_names_peer" "waiting_on_reviewer (reviewer-no-verdict-yet) — bugbot has not returned a verdict for ${_1789_H} after 2400s (budget 2400s, default); failure evidence from coderabbit-cli (no_output) — reviewer-failed applied" "$_1789_line"
run_test "1789_T5.5_result_line_no_false_claim" "0" "$(printf '%s\n' "$_1789_line" | grep -c 'no reviewer failure was detected' || true)"
# Variant: the CLI sleeps past its budget instead (the timeout kept skip).
_1789_reset_processing_globals
loop_head_sha="$_1789_H"
_1789_timed coderabbit-cli 1 0 1 default none 4 "$(_1789_run_cr_cli 0 4 1)"
_1789_timed bugbot 2 4 2400 default none 2400 "$(print_no_verdict_yet bugbot check_not_completed "$_1789_H" "")"
_1789_wk="$(reviewer_loop_emit_waiting_keys)"
run_test "1789_T5.5_kept_skip_no_failure" "1|0" \
  "$(kv_value NO_FAILURE_DETECTED "$_1789_wk")|$(printf '%s\n' "$_1789_wk" | grep -c '^FAILED_PEER_PLATFORMS=' || true)"
run_test "1789_T5.5_kept_skip_label_not_added" "0|0|0" "$(_1789_reconcile 0)"
# Deferred note (c): the defensive branch — reviewer_failed_required set with
# no failure-evidence peer listed (not produced by today's recording, which
# sets the flag from the same peer entries). It fails closed: NO_FAILURE_DETECTED=0,
# no FAILED_PEER_PLATFORMS, and the line states only that the label was applied.
reviewer_failed_required=1
_1789_wk="$(reviewer_loop_emit_waiting_keys)"
run_test "1789_T5.5_defensive_required_without_peer" "0|0" \
  "$(kv_value NO_FAILURE_DETECTED "$_1789_wk")|$(printf '%s\n' "$_1789_wk" | grep -c '^FAILED_PEER_PLATFORMS=' || true)"
run_test "1789_T5.5_defensive_result_line" "waiting_on_reviewer (reviewer-no-verdict-yet) — bugbot has not returned a verdict for ${_1789_H} after 2400s (budget 2400s, default); reviewer-failed applied" \
  "$(reviewer_loop_no_verdict_result_line reviewer-no-verdict-yet)"
# The Codex wait reasons keep their existing line; the failure clause is
# appended only when failure evidence exists.
reviewer_failed_required=0
run_test "1789_T5.5_codex_line_unchanged_without_failure" "waiting_on_reviewer (codex-github-review-pending) — current-head review trigger posted; reviewer has not returned terminal evidence yet" \
  "$(reviewer_loop_no_verdict_result_line codex-github-review-pending)"
platform_peer_evidence+=("coderabbit-cli|skipped|no_output")
run_test "1789_T5.5_codex_line_with_failure_clause" "waiting_on_reviewer (codex-github-reaction-without-review) — current-head review trigger posted; reviewer has not returned terminal evidence yet; failure evidence from coderabbit-cli (no_output) — reviewer-failed applied" \
  "$(reviewer_loop_no_verdict_result_line codex-github-reaction-without-review)"

# --- T4.7: the loop-side Claude handler with a mock companion. A fresh run
# that exits 4 after printing REVIEW_REQUESTED_AT / REVIEW_REQUEST_REF yields
# PLATFORM_<n>_REQUEST_REF and a ledger request_ref; the re-wait invocation
# (same run id and head) passes --adopt-run-id / --adopt-requested-at with
# those values and its own record carries the same request; with only a
# recorded requested_at it passes neither.
_1789_claude_args="$_1789_dir/claude-args.log"
cat > "$_1789_stub_root/scripts/development-workflow/claude-code-action-reviewer.sh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$_1789_claude_args"
printf 'DISPATCH_RESULT=accepted\nREVIEW_REQUESTED_AT=2020-01-01T00:00:07Z\nREVIEW_REQUEST_REF=777\nVERDICT: NO_VERDICT_YET\n'
exit 4
STUB
chmod +x "$_1789_stub_root/scripts/development-workflow/claude-code-action-reviewer.sh"
_1789_reset_processing_globals
_1789_out="$(_1789_run_handler run_claude_code_action_review 30)"
run_test "1789_T4.7_fresh_no_adopt_flags" "0" "$(grep -c -- '--adopt-' "$_1789_claude_args" || true)"
run_test "1789_T4.7_fresh_forwards_request" "2020-01-01T00:00:07Z|777|4" \
  "$(_1789_keys "$_1789_out")|$(kv_value_default EXIT "$_1789_out" "")"
_1789_timed claude-code-action 1 4 1200 default none 30 "$_1789_out"
run_test "1789_T4.7_platform_request_ref" "777|request" "$(_1789_kv PLATFORM_1_REQUEST_REF)|$(_1789_kv PLATFORM_1_REQUESTED_AT_SOURCE)"
_1789_t47_rec="$(_1789_last_record)"
run_test "1789_T4.7_ledger_request_ref" "777|2020-01-01T00:00:07Z" \
  "$(printf '%s' "$_1789_t47_rec" | jq -r '[.request_ref, .requested_at] | join("|")')"
# The next invocation: same run id and head → rewait; the recorded request is
# loaded for the platform and handed to the companion.
_1789_t47_payload="$(_1789_ledger "$(_1789_entry "$_1789_RUN" "1789aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "1789aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" waiting_on_reviewer reviewer-no-verdict-yet "[$_1789_t47_rec]")")"
loop_head_sha="1789aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
reviewer_loop_rewait_mode=1
reviewer_loop_rewait_history_payload="$_1789_t47_payload"
PR_REVIEW_LOOP_RUN_ID="$_1789_RUN" reviewer_loop_rewait_prepare_platform claude-code-action
_1789_out="$(_1789_run_handler run_claude_code_action_review 30)"
run_test "1789_T4.7_rewait_passes_adopt_flags" "1" \
  "$(grep -c -- '--adopt-run-id 777 --adopt-requested-at 2020-01-01T00:00:07Z' "$_1789_claude_args" || true)"
_1789_reset_processing_globals
_1789_timed claude-code-action 1 4 1200 default none 30 "$_1789_out"
run_test "1789_T4.7_rewait_record_carries_request" "777|2020-01-01T00:00:07Z|request" \
  "$(_1789_last_record | jq -r '[.request_ref, .requested_at, .requested_at_source] | join("|")')"
# Only a recorded requested_at (empty ref) → neither flag; the companion dispatches.
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
reviewer_loop_rewait_mode=1
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
reviewer_loop_recorded_request_found=1
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
reviewer_loop_recorded_request_ref=""
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
reviewer_loop_recorded_requested_at="2020-01-01T00:00:07Z"
_1789_out="$(_1789_run_handler run_claude_code_action_review 30)"
run_test "1789_T4.7_requested_at_only_no_flags" "0" "$(grep -c -- '--adopt-' "$_1789_claude_args" || true)"
_1789_rewait_off
# T2.19 (plan D15 claude-code-action row): the loop handler passes the loop
# head as --head-sha, so the companion counts only reviews bound to it; with no
# valid loop head the flag is omitted (the companion rejects a malformed one).
_1789_out="$(_1789_run_handler run_claude_code_action_review 30)"
run_test "1789_T2.19_loop_passes_head_sha" "1" \
  "$(grep -c -- '--head-sha 1789aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$_1789_claude_args" || true)"
_1789_out="$(_1789_handler_loop_head="unknown-head" _1789_run_handler run_claude_code_action_review 30)"
run_test "1789_T2.19_loop_omits_head_sha_without_valid_head" "0" "$(grep -c -- '--head-sha' "$_1789_claude_args" || true)"
_1789_out="$(_1789_handler_loop_head="" _1789_run_handler run_claude_code_action_review 30)"
run_test "1789_T2.19_loop_omits_head_sha_without_head" "0" "$(grep -c -- '--head-sha' "$_1789_claude_args" || true)"
unset reviewer_loop_rewait_history_payload

# ---------------------------------------------------------------------------
# Phase 5 — requests recorded for the head (plan D15) and Greptile binding:
# T2.21 (reviewer_loop_head_recorded_request_refs), T2.15 (fresh-mode reuse),
# T2.14 (regression: a previous-head request answers after the new-head
# invocation begins), T2.16 (Greptile pre-trigger drift), T2.20 (unresolved
# older-revision thread still blocks through the aggregate audit).
# ---------------------------------------------------------------------------
_1789_refs() { reviewer_loop_head_recorded_request_refs "$1" "$2" "$3" | paste -sd ',' -; }
_1789_gr_rec() { _1789_req_rec greptile "${2:-request}" "$1" 2020-01-01T00:00:03Z; }
_1789_t221_payload="$(_1789_ledger \
  "$(_1789_entry run-a "$_1789_H" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet "[$(_1789_gr_rec 9501)]")" \
  "$(_1789_entry run-b "$_1789_H" "$_1789_H" clean "" "[$(_1789_gr_rec 9502),$(_1789_gr_rec 9503 wait_start),$(_1789_gr_rec "")]")" \
  "$(_1789_entry run-c "$_1789_OLD" "$_1789_OLD" waiting_on_reviewer reviewer-no-verdict-yet "[$(_1789_gr_rec 9504)]")" \
  "$(_1789_entry run-d "$_1789_H" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet "[$(_1789_req_rec pr-agent request 9505 2020-01-01T00:00:03Z)]")")"
# --- T2.21
run_test "1789_T2.21_two_runs_waiting_and_clean_both_listed" "9501,9502" "$(_1789_refs "$_1789_t221_payload" "$_1789_H" greptile)"
run_test "1789_T2.21_wait_start_empty_other_head_other_platform_not_listed" "no" \
  "$(_1789_refs "$_1789_t221_payload" "$_1789_H" greptile | grep -E '9503|9504|9505|(^|,)(,|$)' > /dev/null && echo yes || echo no)"
run_test "1789_T2.21_other_platform_listed_for_itself" "9505" "$(_1789_refs "$_1789_t221_payload" "$_1789_H" pr-agent)"
run_test "1789_T2.21_other_head_lists_its_own" "9504" "$(_1789_refs "$_1789_t221_payload" "$_1789_OLD" greptile)"
run_test "1789_T2.21_head_case_insensitive" "9501,9502" \
  "$(_1789_refs "$_1789_t221_payload" "$(printf '%s' "$_1789_H" | tr 'a-f' 'A-F')" greptile)"
run_test "1789_T2.21_unavailable_ledger_nothing" "" \
  "$(_1789_refs '{"schema":"reviewer_loop_history.v1","history_status":"unavailable","entries":[]}' "$_1789_H" greptile)"
run_test "1789_T2.21_unreadable_ledger_nothing" "" "$(_1789_refs 'not json' "$_1789_H" greptile)"
run_test "1789_T2.21_unknown_head_nothing" "" "$(_1789_refs "$_1789_t221_payload" "unknown-1" greptile)"
run_test "1789_T2.21_numeric_ref_listed" "9506" \
  "$(_1789_refs "$(_1789_ledger "$(_1789_entry run-e "$_1789_H" "$_1789_H" clean "" '[{"platform":"greptile","requested_at_source":"request","request_ref":9506}]')")" "$_1789_H" greptile)"
# T2.15 (helper half): a push before persistence — classification_head H0 and
# head_sha H1 — is listed for H0 (its invocation head), never for H1.
_1789_t215_push="$(_1789_ledger "$(_1789_entry run-f "$_1789_OLD" "$_1789_H" waiting_on_reviewer reviewer-no-verdict-yet "[$(_1789_gr_rec 9507)]")")"
run_test "1789_T2.15_push_entry_not_listed_for_new_head" "" "$(_1789_refs "$_1789_t215_push" "$_1789_H" greptile)"
run_test "1789_T2.15_push_entry_listed_for_invocation_head" "9507" "$(_1789_refs "$_1789_t215_push" "$_1789_OLD" greptile)"

# The loop hand-off: reviewer_loop_head_refs_prepare_platform loads the list
# for greptile and pr-agent only, reading the ledger once per invocation and
# reusing a payload already loaded by the re-wait resolution.
reviewer_loop_head_refs_payload_loaded=0
reviewer_loop_rewait_history_payload="$_1789_t221_payload"
loop_head_sha="$_1789_H"
reviewer_loop_head_refs_prepare_platform greptile 42
run_test "1789_T2.15_prepare_greptile_loads_refs" "9501,9502" "$(printf '%s\n' "$reviewer_loop_head_request_refs" | paste -sd ',' -)"
reviewer_loop_head_refs_prepare_platform pr-agent 42
run_test "1789_T2.15_prepare_pr_agent_loads_refs" "9505" "$reviewer_loop_head_request_refs"
reviewer_loop_head_refs_prepare_platform bugbot 42
run_test "1789_T2.15_prepare_other_platform_clears" "" "$reviewer_loop_head_request_refs"
run_test "1789_T2.15_prepare_listed_ref" "yes|no" \
  "$(reviewer_loop_head_refs_prepare_platform greptile 42; reviewer_loop_head_request_ref_listed 9502 && echo yes || echo no)|$(reviewer_loop_head_refs_prepare_platform greptile 42; reviewer_loop_head_request_ref_listed 9504 && echo yes || echo no)"
reviewer_loop_head_refs_payload_loaded=0
reviewer_loop_rewait_history_payload='{"schema":"reviewer_loop_history.v1","history_status":"unavailable","entries":[]}'
reviewer_loop_head_refs_prepare_platform greptile 42
run_test "1789_T2.15_prepare_unavailable_ledger_empty" "" "$reviewer_loop_head_request_refs"
reviewer_loop_head_refs_payload_loaded=0
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
reviewer_loop_rewait_history_payload="$_1789_t221_payload"
loop_head_sha=""
reviewer_loop_head_refs_prepare_platform greptile 42
run_test "1789_T2.15_prepare_no_loop_head_empty" "" "$reviewer_loop_head_request_refs"
loop_head_sha="$_1789_H"
# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
reviewer_loop_head_refs_payload_loaded=0
unset reviewer_loop_rewait_history_payload
reviewer_loop_head_request_refs=""
run_test "1789_T2.15_main_flow_prepares_before_dispatch" "yes" \
  "$(_1789_a="$(awk -v start="$_1789_ret_line" 'NR > start && /^ *reviewer_loop_rewait_prepare_platform "\$platform_name"$/ {print NR; exit}' "$_1789_loop_src")"; \
     _1789_b="$(awk -v start="$_1789_ret_line" 'NR > start && /^ *reviewer_loop_head_refs_prepare_platform "\$platform_name" "\$pr_number"$/ {print NR; exit}' "$_1789_loop_src")"; \
     _1789_c="$(awk -v start="$_1789_ret_line" 'NR > start && /platform_output="\$\(run_platform_review "\$platform_name"/ {print NR; exit}' "$_1789_loop_src")"; \
     [ -n "$_1789_a" ] && [ -n "$_1789_b" ] && [ -n "$_1789_c" ] && [ "$_1789_a" -lt "$_1789_b" ] && [ "$_1789_b" -lt "$_1789_c" ] && echo yes || echo no)"

# --- T2.15 (handler half): Greptile fresh-mode reuse.
_1789_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
_1789_gr_trigger() { printf '[{"id":%s,"user":{"login":"runner"},"created_at":"%s","body":"@greptile review"}]' "$1" "$_1789_now"; }
_1789_gr_up='[{"content":"+1","user":{"login":"greptile-apps[bot]"}}]'
# A trigger inside the age window whose id is listed for H is reused: no post,
# and the reuse is recorded as this invocation's request (D12).
_1789_gh_reset
_1789_fx issue-comments "$(_1789_gr_trigger 9510)"
reviewer_loop_head_request_refs="9510"
_1789_out="$(_1789_run_gh run_greptile_review 600 300)"
run_test "1789_T2.15_greptile_listed_trigger_reused_no_post" "0" "$(_1789_posts)"
run_test "1789_T2.15_greptile_listed_trigger_request_recorded" "${_1789_now}|9510" "$(_1789_keys "$_1789_out")"
run_test "1789_T2.15_greptile_listed_trigger_polled" "yes" \
  "$( [ "$(grep -c 'issues/comments/9510/reactions' "$_1789_gh_dir/calls.log")" -ge 2 ] && echo yes || echo no)"
run_test "1789_T2.15_greptile_listed_trigger_waiting" "waiting_on_reviewer|reviewer-no-verdict-yet|4" "$(_1789_rre "$_1789_out")"
# The same trigger recorded only for H0 (not listed for H) is not reused.
_1789_gh_reset
_1789_fx issue-comments "$(_1789_gr_trigger 9510)"
reviewer_loop_head_request_refs=""
_1789_out="$(_1789_run_gh run_greptile_review 600 300)"
run_test "1789_T2.15_greptile_unlisted_trigger_posts_new" "1|9001" "$(_1789_posts)|$(kv_value_default REVIEW_REQUEST_REF "$_1789_out" "")"
run_test "1789_T2.15_greptile_unlisted_trigger_never_polled" "0" "$(grep -c 'issues/comments/9510/reactions' "$_1789_gh_dir/calls.log" || true)"
# A listed trigger that the bot already acknowledged is spent: post a new one.
_1789_gh_reset
_1789_fx issue-comments "$(_1789_gr_trigger 9511)"
_1789_fx reactions.9511 "$_1789_gr_up"
reviewer_loop_head_request_refs="9511"
_1789_out="$(_1789_run_gh run_greptile_review 600 300)"
run_test "1789_T2.15_greptile_listed_but_answered_posts_new" "1|9001" "$(_1789_posts)|$(kv_value_default REVIEW_REQUEST_REF "$_1789_out" "")"
reviewer_loop_head_request_refs=""
# No loop head and an empty .head.sha → head-sha-unavailable, nothing posted.
_1789_gh_reset
printf '\n' > "$_1789_gh_dir/head"
_1789_out="$(_1789_gh_loop_head="" _1789_run_gh run_greptile_review 2)"
run_test "1789_T2.15_greptile_no_head_escalates" "escalate|head-sha-unavailable|2" "$(_1789_rre "$_1789_out")"
run_test "1789_T2.15_greptile_no_head_posts_nothing" "0" "$(_1789_posts)"
# No loop head but a readable .head.sha → bound to it, as before.
_1789_gh_reset
_1789_out="$(_1789_gh_loop_head="" _1789_run_gh run_greptile_review 2)"
run_test "1789_T2.15_greptile_reads_pr_head_without_loop_head" "waiting_on_reviewer|reviewer-no-verdict-yet|4|$_1789_H" \
  "$(_1789_rre "$_1789_out")|$(kv_value_default PENDING_REVIEW_HEAD_SHA "$_1789_out" "")"

# --- T2.14 regression: trigger T0 (9400) was posted for H0 and sits inside the
# reuse window, but no ledger record holds it for H (=H1 here); the invocation
# posts T1 (9001). The bot then thumbs-up T0, and a Greptile review comment
# written against H0 (original_commit_id H0, commit_id moved to H) is created
# after T1.
_1789_gr_h0_comment="$(_1789_rc 631 "greptile-apps[bot]" "$_1789_H" "$_1789_OLD" "Logic error on the old head" 2099-01-01T00:00:00Z)"
_1789_gr_h1_comment="$(_1789_rc 632 "greptile-apps[bot]" "$_1789_H" "$_1789_H" "Logic error on the current head" 2099-01-01T00:00:01Z)"
_1789_gh_reset
_1789_fx issue-comments "$(_1789_gr_trigger 9400)"
_1789_fx reactions.9400 "$_1789_gr_up"
_1789_fx review-comments@1 "[$_1789_gr_h0_comment]"
_1789_out="$(_1789_run_gh run_greptile_review 2)"
_1789_assert_waiting T2.14_greptile_previous_head_answer greptile "$_1789_out" no_acknowledgement "$_1789_H"
run_test "1789_T2.14_greptile_request_ref_is_t1" "9001|1" "$(kv_value_default REVIEW_REQUEST_REF "$_1789_out" "")|$(_1789_posts)"
run_test "1789_T2.14_greptile_t0_thumbs_up_never_read" "0" "$(grep -c 'issues/comments/9400/reactions' "$_1789_gh_dir/calls.log" || true)"
# Variant: T1 is acknowledged too → clean; the H0 comment is not counted.
_1789_gh_reset
_1789_fx issue-comments "$(_1789_gr_trigger 9400)"
_1789_fx reactions.9400 "$_1789_gr_up"
_1789_fx reactions.9001@1 "$_1789_gr_up"
_1789_fx review-comments@1 "[$_1789_gr_h0_comment]"
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T2.14_greptile_t1_acknowledged_clean_h0_not_counted" "clean||0|0" \
  "$(_1789_rre "$_1789_out")|$(kv_value_default COMMENT_COUNT "$_1789_out" "")"
# ...with an H1 comment as well → needs_fixes listing only the H1 finding.
_1789_fx review-comments@1 "[$_1789_gr_h0_comment,$_1789_gr_h1_comment]"
printf '0\n' > "$_1789_gh_dir/tick"
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T2.14_greptile_only_h1_finding_listed" "needs_fixes|1|Logic error on the current head|0" \
  "$(kv_value_default RESULT "$_1789_out" "")|$(kv_value_default BLOCKING_COUNT "$_1789_out" "")|$(kv_value_default BLOCKING_1_BODY "$_1789_out" "")|$(printf '%s\n' "$_1789_out" | grep -c 'old head' || true)"

# --- T2.16 Greptile pre-trigger findings: a drifted comment created after the
# head commit's committer time is ignored (a trigger is posted); the same
# comment bound to H is an existing finding (nothing posted).
_1789_gh_reset
_1789_fx review-comments "[$_1789_gr_h0_comment]"
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T2.16_greptile_drifted_pre_trigger_ignored" "waiting_on_reviewer|reviewer-no-verdict-yet|4|1" \
  "$(_1789_rre "$_1789_out")|$(_1789_posts)"
_1789_gh_reset
_1789_fx review-comments "[$_1789_gr_h1_comment]"
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T2.16_greptile_bound_pre_trigger_existing_finding" "needs_fixes|existing_findings|1|0" \
  "$(_1789_rre "$_1789_out")|$(_1789_posts)"
# A Greptile CHANGES_REQUESTED review on another revision is not a pre-trigger finding.
_1789_gh_reset
_1789_fx reviews "[{\"id\":13,\"user\":{\"login\":\"greptile-apps[bot]\"},\"state\":\"CHANGES_REQUESTED\",\"submitted_at\":\"2099-01-01T00:00:00Z\",\"commit_id\":\"$_1789_OLD\",\"body\":\"Fix it\"}]"
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T2.16_greptile_other_revision_review_not_a_finding" "waiting_on_reviewer|reviewer-no-verdict-yet|4|1" \
  "$(_1789_rre "$_1789_out")|$(_1789_posts)"

# --- T2.20: the older-revision Greptile finding the D15 filters drop still
# blocks while its thread is unresolved. Composed, because the aggregate audit
# runs in the main flow after the harness return point: (1) Greptile with the
# drifted H0 comment and an acknowledged trigger is clean; (2) greptile's
# GraphQL login is in the audit's bot list; (3) the strict audit counts the
# unresolved H0 thread; (4) the main flow turns a clean aggregate with a
# positive count into needs_fixes / unresolved_review_threads.
_1789_gh_reset
_1789_fx reactions.9001 "$_1789_gr_up"
_1789_fx review-comments "[$_1789_gr_h0_comment]"
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_T2.20_greptile_clean_with_dropped_h0_finding" "clean||0" "$(_1789_rre "$_1789_out")"
_1789_gr_login="$(bot_login_for_platform greptile)"
run_test "1789_T2.20_greptile_in_audit_bot_logins" "greptile-apps" "${_1789_gr_login%\[bot\]}"
run_test "1789_T2.20_strict_audit_counts_unresolved_h0_thread" "1" \
  "$(MOCK_GH_OUTPUT='{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"RT9","isResolved":false,"isOutdated":false,"firstComment":{"nodes":[{"author":{"login":"greptile-apps"},"body":"Logic error on the old head"}]}}]}}' \
     check_unresolved_threads 42 owner/repo strict greptile-apps)"
run_test "1789_T2.20_main_flow_clean_with_threads_becomes_needs_fixes" "yes" \
  "$(awk -v start="$_1789_ret_line" 'NR > start && /if \[ "\$unresolved_thread_count" -gt 0 \]; then/ {f=NR} f && NR > f && NR <= f + 2 && /aggregate_result="needs_fixes"/ {a=1} f && NR > f && NR <= f + 3 && /aggregate_reason="unresolved_review_threads"/ {b=1} END {print (a && b) ? "yes" : "no"}' "$_1789_loop_src")"
unset _1789_t221_payload _1789_t215_push _1789_now _1789_gr_up _1789_gr_h0_comment _1789_gr_h1_comment _1789_gr_login
unset -f _1789_refs _1789_gr_rec _1789_gr_trigger

# ---------------------------------------------------------------------------
# Phase 5 — PR-Agent summary rules (plan D15): rule (a) unit rows (deferred
# note a: any <owner>/<repo>, a GitHub Enterprise host, the unterminated
# review-state block), T2.18, and T2.22. The handler's phases are named as in
# run_pr_agent_review: "Phase 1" (an existing summary, rule (a) only),
# "Phase 2" (the poll, rule (a) or rule (b)), "Phase 3" (classification).
# ---------------------------------------------------------------------------
_1789_pa_marker() { printf '#### (Review updated until commit https://%s/%s/commit/%s)' "${2:-github.com}" "${3:-acme/widgets}" "$1"; }
_1789_pa_block() { printf '<!-- pr-agent-review-state:v1 {"head_sha":"%s","findings":[{"last_seen_head_sha":"%s"}]} -->' "$1" "$1"; }
_1789_pa_body() { printf '## PR Reviewer Guide 🔍\n\n%s\n\nNo major issues detected\n%s' "${1:-}" "${2:-}"; }
# _1789_pa_sum <id> <created_at> <updated_at> <body>
_1789_pa_sum() {
  jq -nc --argjson id "$1" --arg c "$2" --arg u "$3" --arg body "$4" \
    '{id: $id, user: {login: "github-actions[bot]"}, created_at: $c, updated_at: $u,
      html_url: ("https://github.com/acme/widgets/pull/42#issuecomment-" + ($id | tostring)), body: $body}'
}
# _1789_pa_run <id> <status> <conclusion-json> <started_at> <completed_at-json>
_1789_pa_run() {
  printf '{"id":%s,"name":"PR-Agent review","status":"%s","conclusion":%s,"started_at":"%s","completed_at":%s,"check_suite":{"id":555}}' \
    "$1" "$2" "$3" "$4" "$5"
}
# _1789_pa_wf <id> <head_sha> <status> <run_started_at> <updated_at>
_1789_pa_wf() {
  printf '{"id":%s,"workflow_id":77,"event":"pull_request","head_sha":"%s","status":"%s","run_started_at":"%s","updated_at":"%s"}' \
    "$1" "$2" "$3" "$4" "$5"
}
_1789_pa_kept="skipped|no_review|0"

# --- Rule (a) unit rows (pr_agent_summary_marker_names_head).
_1789_ra() { if pr_agent_summary_marker_names_head "$1" "$2"; then echo yes; else echo no; fi; }
run_test "1789_D15a_marker_names_head" "yes" "$(_1789_ra "$(_1789_pa_body "$(_1789_pa_marker "$_1789_H")")" "$_1789_H")"
run_test "1789_D15a_any_owner_repo" "yes" \
  "$(_1789_ra "$(_1789_pa_body "$(_1789_pa_marker "$_1789_H" github.com some-org/other.repo_name)")" "$_1789_H")"
run_test "1789_D15a_enterprise_host" "yes" \
  "$(_1789_ra "$(_1789_pa_body "$(_1789_pa_marker "$_1789_H" ghe.example.com team/svc)")" "$_1789_H")"
run_test "1789_D15a_head_case_insensitive" "yes" \
  "$(_1789_ra "$(_1789_pa_body "$(_1789_pa_marker "$_1789_H")")" "$(printf '%s' "$_1789_H" | tr 'a-f' 'A-F')")"
run_test "1789_D15a_marker_other_head" "no" "$(_1789_ra "$(_1789_pa_body "$(_1789_pa_marker "$_1789_OLD")")" "$_1789_H")"
run_test "1789_D15a_sha_only_in_block" "no" \
  "$(_1789_ra "$(_1789_pa_body "" "$(_1789_pa_block "$_1789_H")")" "$_1789_H")"
run_test "1789_D15a_old_marker_block_names_head" "no" \
  "$(_1789_ra "$(_1789_pa_body "$(_1789_pa_marker "$_1789_OLD")" "$(_1789_pa_block "$_1789_H")")" "$_1789_H")"
run_test "1789_D15a_sha_in_plain_text" "no" "$(_1789_ra "$(_1789_pa_body "Reviewed $_1789_H")" "$_1789_H")"
run_test "1789_D15a_marker_inside_block_not_visible" "no" \
  "$(_1789_ra "$(_1789_pa_body "" "<!-- pr-agent-review-state:v1 $(_1789_pa_marker "$_1789_H") -->")" "$_1789_H")"
run_test "1789_D15a_terminated_block_plus_marker" "yes" \
  "$(_1789_ra "$(_1789_pa_body "$(_1789_pa_marker "$_1789_H")" "$(_1789_pa_block "$_1789_OLD")")" "$_1789_H")"
# Unterminated review-state block: fail closed (not bound), never a crash.
run_test "1789_D15a_unterminated_block_after_marker_not_bound" "no" \
  "$(_1789_ra "$(_1789_pa_body "$(_1789_pa_marker "$_1789_H")" "<!-- pr-agent-review-state:v1 {\"head_sha\":\"$_1789_H\"")" "$_1789_H")"
run_test "1789_D15a_unterminated_block_before_marker_not_bound" "no" \
  "$(_1789_ra "$(_1789_pa_body "<!-- pr-agent-review-state:v1 {" "$(_1789_pa_marker "$_1789_H")")" "$_1789_H")"
run_test "1789_D15a_unterminated_block_no_crash" "0" \
  "$(pr_agent_summary_marker_names_head "<!-- pr-agent-review-state:v1 $(_1789_pa_marker "$_1789_H")" "$_1789_H" 2>&1 | grep -c . || true)"
run_test "1789_D15a_short_head_never_matches" "no" "$(_1789_ra "$(_1789_pa_body "$(_1789_pa_marker 1789dd)")" 1789dd)"
run_test "1789_D15a_marker_without_close_paren" "no" \
  "$(_1789_ra "#### (Review updated until commit https://github.com/acme/widgets/commit/${_1789_H}0)" "$_1789_H")"
run_test "1789_D15a_extra_path_segment" "no" \
  "$(_1789_ra "$(_1789_pa_marker "$_1789_H" github.com acme/widgets/tree)" "$_1789_H")"
run_test "1789_D15a_empty_head_or_body" "no|no" "$(_1789_ra "" "$_1789_H")|$(_1789_ra "$(_1789_pa_marker "$_1789_H")" "")"

# --- T2.18 rule (a) in the handler.
# A summary edited after the committer time whose marker names H0 → not
# accepted; expiry is the no_review kept skip.
_1789_gh_reset
_1789_fx issue-comments "[$(_1789_pa_sum 801 2020-01-01T00:00:01Z 2020-01-01T00:00:40Z "$(_1789_pa_body "$(_1789_pa_marker "$_1789_OLD")")")]"
_1789_out="$(_1789_run_gh run_pr_agent_review 2)"
run_test "1789_T2.18_edited_summary_naming_h0_kept_skip" "$_1789_pa_kept" "$(_1789_rre "$_1789_out")"
# The same summary naming H1 (the head) → accepted in Phase 1, nothing posted.
_1789_gh_reset
_1789_fx issue-comments "[$(_1789_pa_sum 801 2020-01-01T00:00:01Z 2020-01-01T00:00:40Z "$(_1789_pa_body "$(_1789_pa_marker "$_1789_H")")")]"
_1789_out="$(_1789_run_gh run_pr_agent_review 2)"
run_test "1789_T2.18_summary_naming_h1_accepted_phase1" "clean||0|0" "$(_1789_rre "$_1789_out")|$(_1789_posts)"
# Regression — block-only head SHA. (i) Phase 2: a summary that appears after
# Phase 1 with its marker naming H0 while the review-state block's head_sha
# and last_seen_head_sha are H1 → not accepted, kept skip at expiry.
_1789_pa_block_only="$(_1789_pa_body "$(_1789_pa_marker "$_1789_OLD")" "$(_1789_pa_block "$_1789_H")")"
_1789_gh_reset
_1789_fx issue-comments@1 "[$(_1789_pa_sum 802 2020-01-01T00:00:01Z 2020-01-01T00:00:40Z "$_1789_pa_block_only")]"
_1789_out="$(_1789_run_gh run_pr_agent_review 3)"
run_test "1789_T2.18_i_phase2_block_only_head_not_accepted" "$_1789_pa_kept|3" "$(_1789_rre "$_1789_out")|$(_1789_tick)"
# (ii) Phase 1 with the same body returns no verdict: it goes on to request a
# review (one /review posted) and ends in the kept skip.
_1789_gh_reset
_1789_fx issue-comments "[$(_1789_pa_sum 802 2020-01-01T00:00:01Z 2020-01-01T00:00:40Z "$_1789_pa_block_only")]"
_1789_out="$(_1789_run_gh run_pr_agent_review 2)"
run_test "1789_T2.18_ii_phase1_block_only_head_no_verdict" "$_1789_pa_kept|1" "$(_1789_rre "$_1789_out")|$(_1789_posts)"

# --- T2.18 rule (b): the V32 shape. An unedited, marker-free first summary
# whose review-state block holds H, created inside a completed success
# "PR-Agent review" check run window on H, with no active run on H, no
# overlapping branch run on another head, and no earlier /review → accepted.
_1789_pa_first="$(_1789_pa_sum 803 2020-01-01T00:00:30Z 2020-01-01T00:00:30Z "$(_1789_pa_body "" "$(_1789_pa_block "$_1789_H")")")"
_1789_pa_ok_runs="$(_1789_pra_runs "$(_1789_pa_run 20 completed '"success"' 2020-01-01T00:00:10Z '"2020-01-01T00:01:00Z"')")"
_1789_pa_ok_branch="{\"workflow_runs\":[$(_1789_pa_wf 3001 "$_1789_H" completed 2020-01-01T00:00:10Z 2020-01-01T00:01:00Z),$(_1789_pa_wf 2999 "$_1789_OLD" completed 2019-12-31T00:00:00Z 2019-12-31T00:05:00Z)]}"
# _1789_pa_rule_b [fixture-name fixture-value]...: the V32 fixtures, each
# optionally overridden, then one handler run (budget 2).
_1789_pa_rule_b() {
  _1789_gh_reset
  _1789_fx issue-comments "[$_1789_pa_first]"
  _1789_fx check-runs "$_1789_pa_ok_runs"
  _1789_fx branch-runs "$_1789_pa_ok_branch"
  while [ "$#" -ge 2 ]; do _1789_fx "$1" "$2"; shift 2; done
  _1789_run_gh run_pr_agent_review 2
}
_1789_out="$(_1789_pa_rule_b)"
run_test "1789_T2.18_rule_b_v32_shape_accepted" "clean||0" "$(_1789_rre "$_1789_out")"
run_test "1789_T2.18_iii_rule_b_accepted_in_phase2_not_phase1" "1|1" \
  "$(_1789_posts)|$(_1789_stderr_has "first summary 803 is bound to $_1789_H by its PR-Agent review run (D15 rule b)")"
run_test "1789_T2.18_rule_b_reads_branch_runs_of_binding_workflow" "1|1" \
  "$(grep -c 'actions/runs?check_suite_id=555' "$_1789_gh_dir/calls.log" || true)|$(grep 'actions/workflows/77/runs' "$_1789_gh_dir/calls.log" | grep -c 'event=pull_request.*branch=feature/1789-x' || true)"
# Each single failed rule (b) condition leaves it unaccepted.
_1789_out="$(_1789_pa_rule_b issue-comments "[$(_1789_pa_sum 803 2020-01-01T00:00:30Z 2020-01-01T00:00:31Z "$(_1789_pa_body "" "$(_1789_pa_block "$_1789_H")")")]")"
run_test "1789_T2.18_rule_b_edited_not_accepted" "$_1789_pa_kept" "$(_1789_rre "$_1789_out")"
_1789_out="$(_1789_pa_rule_b issue-comments "[$(_1789_pa_sum 803 2020-01-01T00:00:05Z 2020-01-01T00:00:05Z "$(_1789_pa_body "" "$(_1789_pa_block "$_1789_H")")")]")"
run_test "1789_T2.18_rule_b_outside_window_not_accepted" "$_1789_pa_kept" "$(_1789_rre "$_1789_out")"
for _1789_concl in failure cancelled; do
  _1789_out="$(_1789_pa_rule_b check-runs "$(_1789_pra_runs "$(_1789_pa_run 20 completed "\"$_1789_concl\"" 2020-01-01T00:00:10Z '"2020-01-01T00:01:00Z"')")")"
  # Never accepted; the failure-type newest run on H is D8's pr_agent_run_failed.
  run_test "1789_T2.18_rule_b_window_run_${_1789_concl}_not_accepted" "escalate|pr_agent_run_failed|2" "$(_1789_rre "$_1789_out")"
done
_1789_out="$(_1789_pa_rule_b check-runs "$(_1789_pra_runs "$(_1789_pa_run 20 completed '"success"' 2020-01-01T00:00:10Z '"2020-01-01T00:01:00Z"'),$(_1789_pa_run 21 in_progress null 2020-01-01T00:00:50Z null)")")"
run_test "1789_T2.18_rule_b_active_h1_run_not_accepted" "$_1789_pa_kept" "$(_1789_rre "$_1789_out")"
_1789_out="$(_1789_pa_rule_b branch-runs "{\"workflow_runs\":[$(_1789_pa_wf 2998 "$_1789_OLD" completed 2020-01-01T00:00:05Z 2020-01-01T00:00:45Z)]}")"
run_test "1789_T2.18_rule_b_overlapping_h0_run_not_accepted" "$_1789_pa_kept" "$(_1789_rre "$_1789_out")"
_1789_out="$(_1789_pa_rule_b branch-runs "{\"workflow_runs\":[$(_1789_pa_wf 2997 "$_1789_OLD" in_progress 2020-01-01T00:00:05Z 2020-01-01T00:00:06Z)]}")"
run_test "1789_T2.18_rule_b_running_h0_run_not_accepted" "$_1789_pa_kept" "$(_1789_rre "$_1789_out")"
_1789_out="$(_1789_pa_rule_b branch-runs "{\"workflow_runs\":[$(_1789_pa_wf 2996 "$_1789_OLD" completed 2020-01-01T00:00:35Z 2020-01-01T00:00:50Z)]}")"
run_test "1789_T2.18_rule_b_h0_run_started_after_summary_accepted" "clean||0" "$(_1789_rre "$_1789_out")"
_1789_out="$(_1789_pa_rule_b issue-comments "[{\"id\":804,\"user\":{\"login\":\"maintainer\"},\"created_at\":\"2020-01-01T00:00:20Z\",\"updated_at\":\"2020-01-01T00:00:20Z\",\"body\":\"/review\"},$_1789_pa_first]")"
run_test "1789_T2.18_rule_b_earlier_review_comment_not_accepted" "$_1789_pa_kept" "$(_1789_rre "$_1789_out")"
for _1789_failing in check-runs-fail suite-runs-fail branch-runs-fail pull-fail; do
  _1789_out="$(_1789_pa_rule_b "$_1789_failing" 1)"
  run_test "1789_T2.18_rule_b_${_1789_failing}_not_accepted" "$_1789_pa_kept" "$(_1789_rre "$_1789_out")"
done
_1789_out="$(_1789_pa_rule_b suite-runs '{"workflow_runs":[]}')"
run_test "1789_T2.18_rule_b_no_binding_workflow_not_accepted" "$_1789_pa_kept" "$(_1789_rre "$_1789_out")"
# (iii) with a rule (b) condition false (here: edited), the block holding H
# does not bind it either — the block never satisfies rule (a).
_1789_out="$(_1789_pa_rule_b issue-comments "[$(_1789_pa_sum 803 2020-01-01T00:00:30Z 2020-01-01T00:00:59Z "$(_1789_pa_body "" "$(_1789_pa_block "$_1789_H")")")]")"
run_test "1789_T2.18_iii_rule_b_false_block_holding_head_not_accepted" "$_1789_pa_kept" "$(_1789_rre "$_1789_out")"
# A summary that carries a marker (for another head) is never a rule (b)
# candidate, even with every run condition true.
_1789_out="$(_1789_pa_rule_b issue-comments "[$(_1789_pa_sum 805 2020-01-01T00:00:30Z 2020-01-01T00:00:30Z "$(_1789_pa_body "$(_1789_pa_marker "$_1789_OLD")" "$(_1789_pa_block "$_1789_H")")")]")"
run_test "1789_T2.18_marker_for_other_head_not_rule_b_candidate" "$_1789_pa_kept" "$(_1789_rre "$_1789_out")"
# An unterminated review-state block is not a rule (b) candidate (fail closed).
_1789_out="$(_1789_pa_rule_b issue-comments "[$(_1789_pa_sum 806 2020-01-01T00:00:30Z 2020-01-01T00:00:30Z "$(_1789_pa_body "" "<!-- pr-agent-review-state:v1 {\"head_sha\":\"$_1789_H\"")")]")"
run_test "1789_T2.18_unterminated_block_not_rule_b_candidate" "$_1789_pa_kept" "$(_1789_rre "$_1789_out")"
# A /review trigger inside the reuse window that is not listed for H does not
# suppress the new request; the same trigger listed for H does (and is recorded).
_1789_pa_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
_1789_gh_reset
_1789_fx issue-comments "[{\"id\":807,\"user\":{\"login\":\"runner\"},\"created_at\":\"$_1789_pa_now\",\"updated_at\":\"$_1789_pa_now\",\"body\":\"/review\"}]"
reviewer_loop_head_request_refs=""
_1789_out="$(_1789_run_gh run_pr_agent_review 2)"
run_test "1789_T2.18_unlisted_recent_trigger_does_not_suppress_request" "1|" \
  "$(_1789_posts)|$(kv_value_default PR_AGENT_TRIGGER_SKIPPED "$_1789_out" "")"
_1789_gh_reset
_1789_fx issue-comments "[{\"id\":807,\"user\":{\"login\":\"runner\"},\"created_at\":\"$_1789_pa_now\",\"updated_at\":\"$_1789_pa_now\",\"body\":\"/review\"}]"
reviewer_loop_head_request_refs="807"
_1789_out="$(_1789_run_gh run_pr_agent_review 2)"
run_test "1789_T2.18_listed_recent_trigger_reused_and_recorded" "0|recent_review_trigger|${_1789_pa_now}|807" \
  "$(_1789_posts)|$(kv_value_default PR_AGENT_TRIGGER_SKIPPED "$_1789_out" "")|$(_1789_keys "$_1789_out")"
reviewer_loop_head_request_refs=""

# --- T2.22 regression: a delayed older-head first summary arrives after the
# current request. Phase 1: no summary, and the H1 pull_request check run (the
# push's own review request) is in progress, so no /review is posted. A
# pull_request run on H0 that started before the push is still running. An
# unedited marker-free summary is then created while both runs are in
# progress, and the H1 run completes after it (the comment lies inside a
# completed H1 window). Not accepted; the result is the no_review kept skip.
_1789_gh_reset
_1789_fx check-runs "$(_1789_pra_runs "$(_1789_pa_run 30 in_progress null 2020-01-01T00:00:10Z null)")"
_1789_fx issue-comments@1 "[$_1789_pa_first]"
_1789_fx check-runs@2 "$(_1789_pra_runs "$(_1789_pa_run 30 completed '"success"' 2020-01-01T00:00:10Z '"2020-01-01T00:01:00Z"')")"
_1789_fx branch-runs "{\"workflow_runs\":[$(_1789_pa_wf 3001 "$_1789_H" in_progress 2020-01-01T00:00:10Z 2020-01-01T00:00:10Z),$(_1789_pa_wf 2990 "$_1789_OLD" in_progress 2020-01-01T00:00:05Z 2020-01-01T00:00:05Z)]}"
_1789_fx branch-runs@2 "{\"workflow_runs\":[$(_1789_pa_wf 3001 "$_1789_H" completed 2020-01-01T00:00:10Z 2020-01-01T00:01:00Z),$(_1789_pa_wf 2990 "$_1789_OLD" completed 2020-01-01T00:00:05Z 2020-01-01T00:00:50Z)]}"
_1789_out="$(_1789_run_gh run_pr_agent_review 4)"
run_test "1789_T2.22_overlapping_h0_run_kept_skip" "$_1789_pa_kept|4" "$(_1789_rre "$_1789_out")|$(_1789_tick)"
run_test "1789_T2.22_no_review_posted" "0|active_review_in_progress" \
  "$(_1789_posts)|$(kv_value_default PR_AGENT_TRIGGER_SKIPPED "$_1789_out" "")"
# Variant: no overlapping H0 run, but the invocation posted its /review before
# the summary was created → not accepted; when the summary is then edited to
# carry the H1 marker, rule (a) accepts it.
_1789_gh_reset
_1789_fx check-runs@1 "$_1789_pa_ok_runs"
_1789_fx branch-runs "$_1789_pa_ok_branch"
_1789_fx issue-comments@1 "[{\"id\":9001,\"user\":{\"login\":\"runner\"},\"created_at\":\"2020-01-01T00:00:20Z\",\"updated_at\":\"2020-01-01T00:00:20Z\",\"body\":\"/review\"},$_1789_pa_first]"
_1789_out="$(_1789_run_gh run_pr_agent_review 3)"
run_test "1789_T2.22_review_before_summary_kept_skip" "$_1789_pa_kept|1" "$(_1789_rre "$_1789_out")|$(_1789_posts)"
_1789_fx issue-comments@2 "[{\"id\":9001,\"user\":{\"login\":\"runner\"},\"created_at\":\"2020-01-01T00:00:20Z\",\"updated_at\":\"2020-01-01T00:00:20Z\",\"body\":\"/review\"},$(_1789_pa_sum 803 2020-01-01T00:00:30Z 2020-01-01T00:01:30Z "$(_1789_pa_body "$(_1789_pa_marker "$_1789_H")" "$(_1789_pa_block "$_1789_H")")")]"
printf '0\n' > "$_1789_gh_dir/tick"
: > "$_1789_gh_dir/posts.log"
_1789_out="$(_1789_run_gh run_pr_agent_review 3)"
run_test "1789_T2.22_edited_to_h1_marker_rule_a_accepts" "clean||0|2" "$(_1789_rre "$_1789_out")|$(_1789_tick)"
unset _1789_pa_kept _1789_pa_block_only _1789_pa_first _1789_pa_ok_runs _1789_pa_ok_branch _1789_pa_now _1789_failing
unset -f _1789_pa_marker _1789_pa_block _1789_pa_body _1789_pa_sum _1789_pa_run _1789_pa_wf _1789_ra _1789_pa_rule_b

# ---------------------------------------------------------------------------
# #1789 (spec BR 2 / BR 3, PR #1882 review): a polling read GitHub refuses with
# an authorization or permission error (401/403) is failure evidence on every
# platform, never No verdict yet. Rate-limit text and other read failures stay
# transient (keep polling).
# ---------------------------------------------------------------------------
_1789_e403='HTTP 403: Resource not accessible by integration (https://api.github.com/repos/o/r/x)'
_1789_e401='HTTP 401: Bad credentials (https://api.github.com/repos/o/r/x)'
_1789_erl='HTTP 403: You have exceeded a secondary rate limit. Please wait a few minutes before you try again.'
_1789_e502='HTTP 502: Bad Gateway (https://api.github.com/repos/o/r/x)'

# Unit rows: reviewer_loop_gh_read_error_class.
run_test "1789_RD_class_403_resource_not_accessible" "denied" "$(reviewer_loop_gh_read_error_class "$_1789_e403")"
run_test "1789_RD_class_401_bad_credentials" "denied" "$(reviewer_loop_gh_read_error_class "$_1789_e401")"
run_test "1789_RD_class_forbidden_word" "denied" "$(reviewer_loop_gh_read_error_class "gh: Forbidden")"
run_test "1789_RD_class_unauthorized_word" "denied" "$(reviewer_loop_gh_read_error_class "Unauthorized")"
run_test "1789_RD_class_requires_authentication" "denied" "$(reviewer_loop_gh_read_error_class "gh: Requires authentication (HTTP 401)")"
run_test "1789_RD_class_403_secondary_rate_limit_transient" "transient" "$(reviewer_loop_gh_read_error_class "$_1789_erl")"
run_test "1789_RD_class_403_primary_rate_limit_transient" "transient" \
  "$(reviewer_loop_gh_read_error_class "HTTP 403: API rate limit exceeded for installation ID 1.")"
run_test "1789_RD_class_502_transient" "transient" "$(reviewer_loop_gh_read_error_class "$_1789_e502")"
run_test "1789_RD_class_network_transient" "transient" "$(reviewer_loop_gh_read_error_class "dial tcp: i/o timeout")"
run_test "1789_RD_class_404_transient" "transient" "$(reviewer_loop_gh_read_error_class "HTTP 404: Not Found")"
run_test "1789_RD_class_empty_transient" "transient" "$(reviewer_loop_gh_read_error_class "")"
# Unit rows: reviewer_loop_gh_read_denied (file in, detail out, file emptied).
_1789_rd_file="$_1789_dir/rd-err"
printf '\n%s\nsecond line\n' "$_1789_e403" > "$_1789_rd_file"
_1789_rd_rc=0
_1789_rd_detail="$(reviewer_loop_gh_read_denied "$_1789_rd_file" 2>/dev/null)" || _1789_rd_rc=$?
run_test "1789_RD_denied_file_rc_detail" "0|$_1789_e403" "${_1789_rd_rc}|${_1789_rd_detail}"
run_test "1789_RD_denied_file_emptied" "0" "$(wc -c < "$_1789_rd_file" | tr -d ' ')"
printf '%s\n' "$_1789_erl" > "$_1789_rd_file"
_1789_rd_rc=0
_1789_rd_warn="$(reviewer_loop_gh_read_denied "$_1789_rd_file" 2>&1 >/dev/null)" || _1789_rd_rc=$?
run_test "1789_RD_rate_limit_file_not_denied" "1" "$_1789_rd_rc"
run_test "1789_RD_rate_limit_file_warns" "yes" \
  "$(grep -q 'transient, still polling.*secondary rate limit' <<< "$_1789_rd_warn" && echo yes || echo no)"
run_test "1789_RD_rate_limit_file_emptied" "0" "$(wc -c < "$_1789_rd_file" | tr -d ' ')"
_1789_rd_rc=0
reviewer_loop_gh_read_denied "$_1789_dir/no-such-file" >/dev/null 2>&1 || _1789_rd_rc=$?
run_test "1789_RD_missing_file_not_denied" "1" "$_1789_rd_rc"
_1789_rd_rc=0
reviewer_loop_gh_read_denied "" >/dev/null 2>&1 || _1789_rd_rc=$?
run_test "1789_RD_empty_path_not_denied" "1" "$_1789_rd_rc"
# The reasons are not availability reasons: class reviewer_failed, label required.
for _1789_p in copilot greptile devin coderabbit; do
  run_test "1789_RD_reason_not_availability:${_1789_p}" "no" \
    "$(if reviewer_loop_reason_in_list "${_1789_p}-read-denied" "${REVIEWER_LOOP_AVAILABILITY_REASONS[@]}"; then echo yes; else echo no; fi)"
  run_test "1789_RD_compare_token:${_1789_p}" "unavailable" \
    "$(normalize_platform_verdict escalate "REASON=${_1789_p}-read-denied")"
done

# _1789_rd_assert <tag> <platform> <output> <reason>: escalate, exit 2, class
# reviewer_failed, label required, no No verdict yet, stopped at the first read.
_1789_rd_assert() {
  local tag="$1" platform="$2" out="$3" reason="$4"
  _1789_assert_failed "$tag" "$platform" "$out" "$reason"
  run_test "1789_${tag}_not_no_verdict_yet" "|" \
    "$(kv_value_default NO_VERDICT_YET "$out" "")|$(kv_value_default WAIT_EXPIRED_DETAIL "$out" "")"
  run_test "1789_${tag}_stops_at_first_read" "0" "$(_1789_tick)"
}

# --- Copilot: the reviews poll read.
_1789_gh_reset
printf '/pulls/42/reviews|%s\n' "$_1789_e403" > "$_1789_gh_dir/gh-error"
_1789_out="$(_1789_run_gh run_copilot_review 4)"
_1789_rd_assert RD_copilot_reviews_403 copilot "$_1789_out" copilot-read-denied
run_test "1789_RD_copilot_detail" "$_1789_e403" "$(kv_value_default READ_DENIED_DETAIL "$_1789_out" "")"
_1789_gh_reset
printf '/pulls/42/reviews|%s\n' "$_1789_e401" > "$_1789_gh_dir/gh-error"
_1789_out="$(_1789_run_gh run_copilot_review 4)"
run_test "1789_RD_copilot_reviews_401" "escalate|copilot-read-denied|2" "$(_1789_rre "$_1789_out")"
# A 403 rate limit and a 502 stay transient: the wait runs to the budget.
_1789_gh_reset
printf '/pulls/42/reviews|%s\n' "$_1789_erl" > "$_1789_gh_dir/gh-error"
_1789_out="$(_1789_run_gh run_copilot_review 2)"
run_test "1789_RD_copilot_rate_limit_403_not_denied" "waiting_on_reviewer|reviewer-no-verdict-yet|4|2" \
  "$(_1789_rre "$_1789_out")|$(_1789_tick)"
run_test "1789_RD_copilot_rate_limit_403_logged" "yes" \
  "$(grep -q 'transient, still polling' "$_1789_gh_dir/stderr" && echo yes || echo no)"
_1789_gh_reset
printf '/pulls/42/reviews|%s\n' "$_1789_e502" > "$_1789_gh_dir/gh-error"
_1789_out="$(_1789_run_gh run_copilot_review 2)"
run_test "1789_RD_copilot_502_not_denied" "waiting_on_reviewer|reviewer-no-verdict-yet|4" "$(_1789_rre "$_1789_out")"

# --- Greptile: the reactions poll read on the posted trigger.
_1789_gh_reset
printf '/reactions|%s\n' "$_1789_e403" > "$_1789_gh_dir/gh-error"
_1789_out="$(_1789_run_gh run_greptile_review 4)"
_1789_rd_assert RD_greptile_reactions_403 greptile "$_1789_out" greptile-read-denied
run_test "1789_RD_greptile_trigger_posted_once" "1|9001" \
  "$(_1789_posts)|$(kv_value_default REVIEW_COMMENT_ID "$_1789_out" "")"
_1789_gh_reset
printf '/reactions|%s\n' "$_1789_erl" > "$_1789_gh_dir/gh-error"
_1789_out="$(_1789_run_gh run_greptile_review 2)"
run_test "1789_RD_greptile_rate_limit_403_not_denied" "waiting_on_reviewer|reviewer-no-verdict-yet|4" "$(_1789_rre "$_1789_out")"

# --- Devin: reviews, check-runs, and statuses poll reads.
for _1789_rd_ep in /pulls/42/reviews /check-runs /statuses; do
  _1789_gh_reset
  # (A refused Phase 1 findings read reads as empty, as before; the poll
  # read is the one that classifies the refusal.)
  printf '%s|%s\n' "$_1789_rd_ep" "$_1789_e403" > "$_1789_gh_dir/gh-error"
  _1789_out="$(_1789_run_gh run_devin_review 300 60)"
  _1789_rd_assert "RD_devin_${_1789_rd_ep//\//_}_403" devin "$_1789_out" devin-read-denied
done
_1789_gh_reset
printf '/check-runs|%s\n' "$_1789_erl" > "$_1789_gh_dir/gh-error"
_1789_out="$(_1789_run_gh run_devin_review 2)"
run_test "1789_RD_devin_rate_limit_403_kept_skip" "skipped|no_check_run|0|1" \
  "$(_1789_rre "$_1789_out")|$(kv_value_default NO_VERDICT_YET "$_1789_out" "")"

# --- CodeRabbit: bound-review, failure/success status, and activity reads.
for _1789_rd_ep in /pulls/42/reviews /statuses /issues/42/comments; do
  _1789_gh_reset
  printf '%s|%s\n' "$_1789_rd_ep" "$_1789_e403" > "$_1789_gh_dir/gh-error"
  _1789_out="$(_1789_run_gh run_coderabbit_review 5)"
  _1789_rd_assert "RD_coderabbit_${_1789_rd_ep//\//_}_403" coderabbit "$_1789_out" coderabbit-read-denied
done
_1789_gh_reset
printf '/pulls/42/reviews|%s\n' "$_1789_erl" > "$_1789_gh_dir/gh-error"
_1789_out="$(_1789_run_gh run_coderabbit_review 3)"
run_test "1789_RD_coderabbit_rate_limit_403_kept_skip" "skipped|no_review|0|1" \
  "$(_1789_rre "$_1789_out")|$(kv_value_default NO_VERDICT_YET "$_1789_out" "")"
# Unit rows: the status counters keep stderr out of stdout with the new
# optional third argument and still print an integer.
_1789_gh_reset
printf '/statuses|%s\n' "$_1789_e403" > "$_1789_gh_dir/gh-error"
: > "$_1789_rd_file"
run_test "1789_RD_coderabbit_failed_count_denied_prints_zero" "0" "$(_1789_cr_count owner/repo "$_1789_H" "$_1789_rd_file")"
run_test "1789_RD_coderabbit_failed_count_captures_stderr" "denied" \
  "$(reviewer_loop_gh_read_error_class "$(cat "$_1789_rd_file")")"

# --- Ronda and Bugbot: already failure evidence (any failed check-run read
# escalates fetch-failed); a 403 there is never No verdict yet.
_1789_gh_reset
printf '/check-runs|%s\n' "$_1789_e403" > "$_1789_gh_dir/gh-error"
_1789_out="$(_1789_run_gh run_ronda_review 4)"
_1789_rd_assert RD_ronda_check_runs_403 ronda "$_1789_out" fetch-failed
_1789_gh_reset
printf '/check-runs|%s\n' "$_1789_e403" > "$_1789_gh_dir/gh-error"
_1789_out="$(_1789_run_gh run_bugbot_review 4)"
_1789_rd_assert RD_bugbot_check_runs_403 bugbot "$_1789_out" fetch-failed
unset _1789_e403 _1789_e401 _1789_erl _1789_e502 _1789_rd_file _1789_rd_rc _1789_rd_detail _1789_rd_warn _1789_rd_ep
unset -f _1789_rd_assert

unset _1789_T0 _1789_kv_file _1789_rec_verdict _1789_rec_waiting _1789_rec_replay _1789_t53_payload _1789_t212_payload
unset _1789_section _1789_wk _1789_line _1789_claude_args _1789_t47_rec _1789_t47_payload
unset -f _1789_timed _1789_kv _1789_has_key _1789_last_record

unset _1789_wait_entry _1789_rec_bb _1789_rw _1789_push_entry _1789_nf_entry _1789_k _1789_pl _1789_rl _1789_hl
unset -f _1789_rewait _1789_rewait_none _1789_rewait_off _1789_stderr_has _1789_count_body

unset _1789_rec_log _1789_main_calls _1789_loop_start _1789_persist_line _1789_rc _1789_err
unset -f _1789_o _1789_reconcile 2>/dev/null || true

unset _1789_H _1789_OLD _1789_gh_bin _1789_gh_dir _1789_state _1789_concl _1789_saved_t22_branch
unset _1789_t22_budget _1789_t22_src _1789_t22_adj _1789_t22_poll
unset -f _1789_gh_reset _1789_fx _1789_tick _1789_posts _1789_run_gh _1789_rre _1789_assert_waiting \
  _1789_assert_kept_skip _1789_assert_failed _1789_bb_run _1789_dv_run _1789_cr_status _1789_cr_count \
  _1789_pra _1789_pra_runs 2>/dev/null || true


unset _1789_RUN _1789_H1
unset -f _1789_entry _1789_ledger _1789_req_rec _1789_state _1789_recorded _1789_keys 2>/dev/null || true
unset _1789_ret_line _1789_helpers_ok _1789_fn _1789_fn_line _1789_case _1789_r _1789_reason _1789_flag _1789_expected
unset _1789_nvy_payload _1789_out _1789_stub_root _1789_body _1789_tag _1789_expected_result _1789_expected_detail _1789_expected_exit
unset _1789_cr_repo _1789_cr_bin _1789_cr_head _1789_cr_out _1789_handler_overrides
unset _1789_nvy_head
unset -f _1789_fc _1789_label _1789_reset_processing_globals _1789_stub_companion _1789_run_handler _1789_run_cr_cli _1789_real_git 2>/dev/null || true

# --- T6.1 (plan Phase 6, AC-14): documentation assertions -------------------
# Protocol 93 carries the canonical section, its subsections, and the D2
# table; Protocol 91's Step 7 table carries every D11 runner row and the
# failure statement; each guide in the plan's Documentation Updates names the
# No verdict yet reason or its kept skip and links the canonical section.
_1789_doc_dir="$REPO_ROOT/docs/workflow/development-workflow"
_1789_p93="$_1789_doc_dir/protocols/93-automated-reviewer-loop-protocol.md"
_1789_p91="$_1789_doc_dir/protocols/91-orchestrate-work-protocol.md"
_1789_doc_has() {
  # _1789_doc_has <file> <fixed string> → yes|no
  if [ -f "$1" ] && grep -Fq -- "$2" "$1"; then printf 'yes\n'; else printf 'no\n'; fi
}
for _1789_h in \
    '### Reviewer wait budgets and outcome classes (#1789)' \
    '#### Outcome classes' \
    '#### Built-in wait budgets' \
    '#### Configuring budgets' \
    '#### Precedence across platforms' \
    '#### The `reviewer-failed` label rule' \
    '#### Automatic re-wait' \
    '#### Timing and waiting keys' \
    '#### Current-revision binding'; do
  run_test "1789_T6.1_p93_heading:${_1789_h}" "yes" "$(_1789_doc_has "$_1789_p93" "$_1789_h")"
done
for _1789_h in \
    '| `bugbot` | 2400 |' \
    '| `codex-github` | 1800 |' \
    '| `greptile`, `devin`, `coderabbit`, `coderabbit-cli`, `local-ai-reviewer`, `pr-agent`, `claude-code-action`, `copilot`, `haystack`, `ronda` | 1200 |' \
    '| `devin` on `spec/*` or `implementation-plan/*` | `PR_REVIEW_LOOP_DOC_MAX_WAIT` (default 180) |'; do
  run_test "1789_T6.1_p93_d2_row:${_1789_h}" "yes" "$(_1789_doc_has "$_1789_p93" "$_1789_h")"
done
# The D2 table in Protocol 93 agrees with the built-in defaults the loop uses.
run_test "1789_T6.1_p93_d2_matches_builtin_defaults" "2400|1800|1200|1200" \
  "$(reviewer_wait_budget_builtin_default bugbot)|$(reviewer_wait_budget_builtin_default codex-github)|$(reviewer_wait_budget_builtin_default local-ai-reviewer)|$(reviewer_wait_budget_builtin_default claude-code-action)"
for _1789_h in \
    '| `waiting_on_reviewer` (exit code 4) with `NO_VERDICT_REWAIT=available` |' \
    '| `waiting_on_reviewer` (exit code 4) with `NO_VERDICT_REWAIT=used` |' \
    '| `waiting_on_reviewer` (exit code 4) with `NO_VERDICT_REWAIT=untracked` |' \
    '| `waiting_on_reviewer` (exit code 4) with `NO_VERDICT_REWAIT` absent or any other value |' \
    '| Result of the automatic re-wait run |' \
    '- `NO_FAILURE_DETECTED=1`: state that no reviewer failure was detected.' \
    '- `NO_FAILURE_DETECTED=0` with a non-empty `FAILED_PEER_PLATFORMS`' \
    '- `NO_FAILURE_DETECTED=0` with `FAILED_PEER_PLATFORMS` absent or empty' \
    '- `NO_FAILURE_DETECTED` absent or any other value: make no failure statement'; do
  run_test "1789_T6.1_p91_step7_row:${_1789_h}" "yes" "$(_1789_doc_has "$_1789_p91" "$_1789_h")"
done
run_test "1789_T6.1_p91_single_waiting_row_removed" "no" \
  "$(_1789_doc_has "$_1789_p91" '| `waiting_on_reviewer` (exit code 4)     |')"
for _1789_g in bugbot greptile devin coderabbit copilot codex-github claude-code-action \
    haystack-triage haystack local-ai-reviewer pr-agent ronda pr-review-platform; do
  _1789_gf="$_1789_doc_dir/integrations/${_1789_g}.md"
  if [ -f "$_1789_gf" ] && grep -Eq 'reviewer-no-verdict-yet|NO_VERDICT_YET=1|NO_VERDICT_REWAIT' "$_1789_gf"; then
    _1789_r=yes
  else
    _1789_r=no
  fi
  run_test "1789_T6.1_guide_names_no_verdict_yet:${_1789_g}" "yes" "$_1789_r"
  run_test "1789_T6.1_guide_links_canonical_section:${_1789_g}" "yes" \
    "$(_1789_doc_has "$_1789_gf" '93-automated-reviewer-loop-protocol.md#reviewer-wait-budgets-and-outcome-classes-1789')"
done
unset _1789_doc_dir _1789_p93 _1789_p91 _1789_h _1789_g _1789_gf _1789_r
unset -f _1789_doc_has

rm -rf "$_1789_dir"
branch_name="$_1789_saved_branch"
config_file="$_1789_saved_config"
changed_files_count="$_1789_saved_changed"
unset _1789_dir _1789_saved_branch _1789_saved_config _1789_saved_changed _1789_none_cfg _1789_p _1789_v _1789_raw
unset _1789_invalid_n _1789_warn _1789_n _1789_log _1789_err _1789_rc _1789_loop_src _1789_e4 _1789_e13_empty
unset -f _1789_cfg _1789_read 2>/dev/null || true

echo "=== Area 1789 complete ==="

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
