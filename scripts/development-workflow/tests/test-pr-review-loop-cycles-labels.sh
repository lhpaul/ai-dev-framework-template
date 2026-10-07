#!/usr/bin/env bash
# test-pr-review-loop-cycles-labels.sh — pr-review-loop.sh harness: cycle
# limits, regression/reviewer-failed labels, and the rate-limit ready-phase
# gate.
# duration: 20
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
#   Area 10c: reviewer-loop max_cycles / max_total_cycles enforcement (#1502)
#   Area 11: regression-label auto-restore (Option C, issue #805)
#   Area 12: reviewer-failed label sync (issue #804)
#   Area 12b: rate-limit-aware ready-phase gate (issue #1509)
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop-cycles-labels.sh [--area <name>]... [--list-areas]
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

# ---------------------------------------------------------------------------
# Area 10c: reviewer-loop max_cycles / max_total_cycles enforcement (#1502,
# dual-cap follow-up per operator decision on PR #1507's review)
#
# reviewer_loop_history_entries_count, reviewer_loop_resolve_max_cycles,
# reviewer_loop_resolve_max_total_cycles, reviewer_loop_cap_exceeded,
# reviewer_loop_cycle_count_unavailable_should_escalate,
# reviewer_loop_resolve_cycle_counts, and reviewer_loop_resolve_run_id are
# all defined before the HARNESS_MODE return point and are therefore
# callable directly, like restore_regression_label_if_missing in Area 11.
#
# Protocol 91:1719 documents a PER-RUN cap ("Initialize cycle = 0 once per
# orchestration run ... escalate when the run reaches max_cycles"). A
# per-run-only cap leaves total effort unbounded across many resumed
# orchestration runs, so a second, never-resetting LIFETIME ceiling is
# layered on top. These tests exercise the actual enforcement functions for
# both axes, not simulated logic.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 10c: reviewer-loop max_cycles / max_total_cycles enforcement (#1502) ==="

# --- reviewer_loop_resolve_run_id ---

unset PR_REVIEW_LOOP_RUN_ID
# Note: a `case` statement directly inside `$( ... )` fails to parse on
# bash 3.2 (macOS default) — the `)` closing a case pattern is misread as
# the command-substitution terminator. Use `[[ ... == prefix* ]]` instead.
run_test "run_id_auto_generated_has_prefix" "yes" "$(
  _rid="$(reviewer_loop_resolve_run_id)"
  if [[ "$_rid" == auto-* ]]; then echo yes; else echo no; fi
)"
run_test "run_id_explicit_env_honored_verbatim" "my-stable-run-42" \
  "$(PR_REVIEW_LOOP_RUN_ID=my-stable-run-42 reviewer_loop_resolve_run_id)"

# --- reviewer_loop_history_entries_count <body> <run_id> ---
# Counts Protocol 91's per-run `cycle` value (run_count, scoped to the
# queried run_id) and a separate never-resetting lifetime_count. Both only
# count prior entries whose result is needs_fixes or needs_rerun, deduped
# by distinct head_sha (unchanged refinements from the earlier review
# round — see the block comment above reviewer_loop_history_entries_count
# in pr-review-loop.sh).

run_test "cycles_entries_count_empty_body" "0 0 available" \
  "$(reviewer_loop_history_entries_count "" "run-x")"

_mc_no_marker_body="### Automated Reviewer Loop Summary
*Posted automatically by \`pr-review-loop.sh\`.*"
run_test "cycles_entries_count_no_marker" "0 0 available" \
  "$(reviewer_loop_history_entries_count "$_mc_no_marker_body" "run-x")"

run_test "small_findings_docs_path_non_shipped" "yes" \
  "$(reviewer_loop_path_is_non_shipped_artifact "docs/other/example.md" && echo yes || echo no)"
run_test "small_findings_workflow_path_normative_not_non_shipped" "no" \
  "$(reviewer_loop_path_is_non_shipped_artifact "docs/workflow/example.md" && echo yes || echo no)"
run_test "small_findings_tests_path_non_shipped" "yes" \
  "$(reviewer_loop_path_is_non_shipped_artifact "scripts/development-workflow/tests/test-pr-review-loop.sh" && echo yes || echo no)"
run_test "small_findings_source_path_shipped" "no" \
  "$(reviewer_loop_path_is_non_shipped_artifact "scripts/development-workflow/pr-review-loop.sh" && echo yes || echo no)"
run_test "small_findings_source_test_filename_shipped_without_test_dir" "no" \
  "$(reviewer_loop_path_is_non_shipped_artifact "src/foo.test.ts" && echo yes || echo no)"
run_test "small_findings_all_paths_requires_a_path" "no" \
  "$(printf '\n' | reviewer_loop_all_paths_non_shipped && echo yes || echo no)"
run_test "small_findings_all_paths_rejects_mixed_source" "no" \
  "$(printf '%s\n' "docs/a.md" "src/app.ts" | reviewer_loop_all_paths_non_shipped && echo yes || echo no)"
run_test "small_findings_all_paths_accepts_docs_tests" "yes" \
  "$(printf '%s\n' "docs/a.md" "tests/a.test.sh" | reviewer_loop_all_paths_non_shipped && echo yes || echo no)"
run_test "small_findings_required_rounds_default" "2" \
  "$(unset PR_REVIEW_LOOP_SMALL_FINDINGS_STOP_ROUNDS; reviewer_loop_small_findings_required_rounds 2>/dev/null)"
run_test "small_findings_required_rounds_env" "3" \
  "$(PR_REVIEW_LOOP_SMALL_FINDINGS_STOP_ROUNDS=3 reviewer_loop_small_findings_required_rounds 2>/dev/null)"
run_test "small_findings_paths_from_output" "docs/a.md tests/b.sh" "$(
  _sf_paths_output=$'RESULT=needs_fixes\nBLOCKING_COUNT=2\nBLOCKING_1_PATH=docs/a.md\nBLOCKING_2_PATH=tests/b.sh'
  reviewer_loop_blocking_paths_from_output "$_sf_paths_output" 2 | tr '\n' ' ' | sed 's/[[:space:]]$//'
)"

_sf_head="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
_sf_history_payload="$(jq -n --arg h "$_sf_head" '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [
    {iteration: 1, result: "needs_fixes", small_findings_only: true,
     classification_head: $h, contributing_platforms: ["local-ai-reviewer"],
     reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]},
    {iteration: 2, result: "needs_fixes", small_findings_only: true,
     classification_head: $h, contributing_platforms: ["local-ai-reviewer"],
     reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]}
  ]
}')"
_sf_history_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_sf_history_payload" | jq '.')
\`\`\`"
run_test "small_findings_prior_consecutive_counts_tail" "2 exhausted" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$_sf_history_body" "$_sf_head")")"

_sf_history_interrupted_payload="$(jq -n --arg h "$_sf_head" '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [
    {iteration: 1, result: "needs_fixes", small_findings_only: true,
     classification_head: $h, contributing_platforms: ["local-ai-reviewer"],
     reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]},
    {iteration: 2, result: "needs_fixes", small_findings_only: false,
     classification_head: $h, contributing_platforms: ["local-ai-reviewer"],
     reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]},
    {iteration: 3, result: "needs_fixes", small_findings_only: true,
     classification_head: $h, contributing_platforms: ["local-ai-reviewer"],
     reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]}
  ]
}')"
_sf_history_interrupted_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_sf_history_interrupted_payload" | jq '.')
\`\`\`"
run_test "small_findings_prior_consecutive_stops_at_non_tail" "1 not_small" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$_sf_history_interrupted_body" "$_sf_head")")"
run_test "small_findings_main_branch_requires_zero_thread_audit" "yes" \
  "$(
    _sf_loop_src="$(cat "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
    if grep -qF '[ "$unresolved_thread_count" -eq 0 ]' <<<"$_sf_loop_src"; then
      echo yes
    else
      echo no
    fi
  )"
unset _sf_paths_output _sf_history_payload _sf_history_body
unset _sf_history_interrupted_payload _sf_history_interrupted_body _sf_loop_src
# _sf_head kept for #1652 scenario block below

# ===========================================================================
# #1652 small-finding terminal policy scenarios (1-11, 14 + sub-scenarios)
# ===========================================================================
_sf_other="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
_sf_finding() {
  jq -cn --arg path "$1" --arg platform "${2:-local-ai-reviewer}" --arg body "${3:-}" \
    '{path: $path, platform: $platform, body: $body}'
}
_sf_ledger() {
  printf '%s\n' "### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$1" | jq '.')
\`\`\`"
}
_sf_is_small() {
  if printf '%s\n' "$@" | reviewer_loop_all_findings_are_small; then echo yes; else echo no; fi
}

# --- Scenario 1: normative document patterns ---
for _p in \
  "REVIEW.md" "AGENTS.md" "CLAUDE.md" "GEMINI.md" "LLM_RULES.md" ".ai-dev-workflow.yaml" \
  ".claude/agents/reviewer.md" ".cursor/rules/workflow.mdc" ".codex/skills/workflow/SKILL.md" ".agents/skills/run-item/SKILL.md" \
  "docs/workflow/protocols/x.md" "docs/best-practices/1-general.md" \
  "docs/specs/developments/x/1_x_specs.md" "docs/testing/workflow/x.smoke-test.md" \
  "docs/project/1-business-domain.md"; do
  run_test "1652_s1_normative_${_p//\//_}" "yes" \
    "$(reviewer_loop_path_is_normative_document "$_p" && echo yes || echo no)"
done
for _p in "tests/fixtures/x.json" "__snapshots__/x.snap" "CHANGELOG.md" "scripts/development-workflow/pr-review-loop.sh"; do
  run_test "1652_s1_reject_${_p//\//_}" "no" \
    "$(reviewer_loop_path_is_normative_document "$_p" && echo yes || echo no)"
done

# --- Scenario 2: normative path never small ---
_sf_spec="docs/specs/developments/x/1_x_specs.md"
run_test "1652_s2_matrix_body" "no" \
  "$(_sf_is_small "$(_sf_finding "$_sf_spec" local-ai-reviewer "the decision matrix is wrong")")"
run_test "1652_s2_trailing_whitespace" "no" \
  "$(_sf_is_small "$(_sf_finding "$_sf_spec" local-ai-reviewer "trailing whitespace")")"
run_test "1652_s2_no_listed_term" "no" \
  "$(_sf_is_small "$(_sf_finding "$_sf_spec" local-ai-reviewer "required error handling is missing")")"

# --- Scenario 3: non-normative non-shipped CHANGELOG ---
run_test "1652_s3_changelog_cosmetic_small" "yes" \
  "$(_sf_is_small "$(_sf_finding "CHANGELOG.md" local-ai-reviewer "trailing whitespace")")"
run_test "1652_s3_changelog_contract_not_small" "no" \
  "$(_sf_is_small "$(_sf_finding "CHANGELOG.md" local-ai-reviewer "the decision matrix is wrong")")"

# --- Scenario 4: contract-surface table ---
run_test "1652_s4_acceptance" "acceptance_criteria" \
  "$(reviewer_loop_finding_touches_contract_surface "missing acceptance criteria here")"
run_test "1652_s4_decision" "decision_gates_and_matrices" \
  "$(reviewer_loop_finding_touches_contract_surface "broken decision gate")"
run_test "1652_s4_parser" "parser_and_input_behavior" \
  "$(reviewer_loop_finding_touches_contract_surface "parser mishandles input")"
run_test "1652_s4_scope" "scope_and_coverage" \
  "$(reviewer_loop_finding_touches_contract_surface "this is out of scope")"
run_test "1652_s4_fail_closed" "fail_closed_semantics" \
  "$(reviewer_loop_finding_touches_contract_surface "not fail-closed")"
run_test "1652_s4_state" "state_and_status_models" \
  "$(reviewer_loop_finding_touches_contract_surface "invalid state machine transition")"
run_test "1652_s4_telemetry" "telemetry_and_contracts" \
  "$(reviewer_loop_finding_touches_contract_surface "stdout key missing")"
run_test "1652_s4_proof" "proof_obligations" \
  "$(reviewer_loop_finding_touches_contract_surface "missing proof obligation")"
run_test "1652_s4_reject_typo" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "typo in heading" || echo NONE)"
run_test "1652_s4_reject_trailing" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "trailing whitespace" || echo NONE)"
run_test "1652_s4_reject_caps" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "heading capitalisation" || echo NONE)"

# --- Scenario 4a: portable boundaries (POSIX, not \b) ---
run_test "1652_s4a_decision_gate_matches" "decision_gates_and_matrices" \
  "$(reviewer_loop_finding_touches_contract_surface "a decision gate failed")"
run_test "1652_s4a_delegates_no_match" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "the agent delegates work" || echo NONE)"

# --- Scenario 4b: multi-digit AC identifiers ---
for _ac in "AC-1" "AC-9" "AC-10" "AC-147"; do
  run_test "1652_s4b_${_ac}" "acceptance_criteria" \
    "$(reviewer_loop_finding_touches_contract_surface "criterion ${_ac} unmet")"
done
run_test "1652_s4b_AC_alone" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "see AC- alone" || echo NONE)"

# --- Scenario 5: contract on CHANGELOG is not small ---
run_test "1652_s5_changelog_contract" "no" \
  "$(_sf_is_small "$(_sf_finding "CHANGELOG.md" x "touches a decision matrix")")"

# --- Scenario 6: cosmetic on CHANGELOG is small ---
run_test "1652_s6_changelog_cosmetic" "yes" \
  "$(_sf_is_small "$(_sf_finding "CHANGELOG.md" x "trailing whitespace")")"

# --- Scenario 6a: bare common words still small ---
for _pair in \
  "state|the heading state is inconsistent" \
  "scope|a typo in the scope section" \
  "status|the status column is misaligned" \
  "gate|the gate heading needs a capital" \
  "proof|fix the proof reading typo" \
  "parse|parse is misspelled here" \
  "contract|the contract section has a trailing space"; do
  _word="${_pair%%|*}"
  _body="${_pair#*|}"
  run_test "1652_s6a_bare_${_word}" "NONE" \
    "$(reviewer_loop_finding_touches_contract_surface "$_body" || echo NONE)"
  run_test "1652_s6a_small_${_word}" "yes" \
    "$(_sf_is_small "$(_sf_finding "CHANGELOG.md" x "$_body")")"
done

# --- Scenario 7: all_findings_are_small mixed ---
_sf_a="$(_sf_finding "CHANGELOG.md" a "trailing whitespace")"
_sf_b="$(_sf_finding "tests/x.sh" b "typo")"
_sf_c="$(_sf_finding "CHANGELOG.md" c "decision matrix wrong")"
run_test "1652_s7_all_small" "yes" "$(_sf_is_small "$_sf_a" "$_sf_b")"
run_test "1652_s7_one_not_small" "no" "$(_sf_is_small "$_sf_a" "$_sf_b" "$_sf_c")"

# --- Scenario 7f: empty array / empty path fail-closed ---
run_test "1652_s7f_empty_array" "no" \
  "$(printf '' | reviewer_loop_all_findings_are_small && echo yes || echo no)"
run_test "1652_s7f_empty_path" "no" \
  "$(_sf_is_small "$(_sf_finding "" x "trailing whitespace")" "$_sf_a")"

# --- Scenario 7a: same path, cosmetic + contract — not deduped ---
_sf_same_cosmetic="$(_sf_finding "CHANGELOG.md" a "trailing whitespace")"
_sf_same_contract="$(_sf_finding "CHANGELOG.md" a "decision matrix wrong")"
run_test "1652_s7a_pairing_survives" "no" \
  "$(_sf_is_small "$_sf_same_cosmetic" "$_sf_same_contract")"

# --- Scenario 7b / 7b-i: \n normalisation ---
_sf_nl_body='some prose\ndecision matrix is wrong'
run_test "1652_s7b_normalized_match" "decision_gates_and_matrices" \
  "$(reviewer_loop_finding_touches_contract_surface "$(reviewer_loop_normalize_finding_body_for_match "$_sf_nl_body")")"
run_test "1652_s7b_raw_would_miss" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "$_sf_nl_body" || echo NONE)"
run_test "1652_s7bi_same_either_way" "decision_gates_and_matrices" \
  "$(reviewer_loop_finding_touches_contract_surface "$(reviewer_loop_normalize_finding_body_for_match "$_sf_nl_body")")"

# --- Scenario 7d: hostile characters in JSON fields ---
_sf_tab_path=$'docs/notes/x.md\textra'
_sf_tab_body=$'decision matrix\there'
_sf_quote_body='says "decision matrix" clearly'
_sf_bs_body='path\\decision matrix ok'
run_test "1652_s7d_tab_path" "no" \
  "$(_sf_is_small "$(_sf_finding "$_sf_tab_path" x "decision matrix wrong")")"
# Prove the path survived JSON round-trip (still contains a tab) and classification
# used the body contract term (blocked_by=contract_surface, not shipped_path).
run_test "1652_s7d_tab_path_intact_fields" "contract_surface" \
  "$(printf '%s\n' "$(_sf_finding "$_sf_tab_path" x "decision matrix wrong")" | reviewer_loop_small_findings_content_analysis | jq -r '.blocked_by')"
run_test "1652_s7d_tab_path_has_tab" "yes" \
  "$(printf '%s' "$(_sf_finding "$_sf_tab_path" x "x")" | jq -r '.path' | grep -F $'\t' > /dev/null && echo yes || echo no)"
run_test "1652_s7d_tab_body" "decision_gates_and_matrices" \
  "$(reviewer_loop_finding_touches_contract_surface "$(reviewer_loop_normalize_finding_body_for_match "$_sf_tab_body")")"
run_test "1652_s7d_quote_body" "decision_gates_and_matrices" \
  "$(reviewer_loop_finding_touches_contract_surface "$_sf_quote_body")"
run_test "1652_s7d_backslash_body" "decision_gates_and_matrices" \
  "$(reviewer_loop_finding_touches_contract_surface "$_sf_bs_body")"

# --- Scenario 7c: platform attribution in content analysis ---
_sf_plat="$(_sf_finding "CHANGELOG.md" "coderabbit" "decision matrix wrong")"
run_test "1652_s7c_platform_on_record" "coderabbit" \
  "$(printf '%s' "$_sf_plat" | jq -r '.platform')"
run_test "1652_s7c_not_small" "no" "$(_sf_is_small "$_sf_plat")"

# --- Scenario 7e: stored body is raw, not normalised ---
_sf_raw_out="$(reviewer_loop_blocking_findings_from_output \
  $'RESULT=needs_fixes\nBLOCKING_COUNT=1\nBLOCKING_1_PATH=CHANGELOG.md\nBLOCKING_1_BODY=some prose\\ndecision matrix is wrong' \
  1 local-ai-reviewer)"
run_test "1652_s7e_raw_body_preserved" "some prose\\ndecision matrix is wrong" \
  "$(printf '%s' "$_sf_raw_out" | jq -r '.body')"

# --- Scenario 8: prior count stops at stale head ---
_sf_s8_payload="$(jq -n --arg h "$_sf_head" --arg o "$_sf_other" '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [
    {iteration: 1, small_findings_only: true, classification_head: $o,
     contributing_platforms: ["local-ai-reviewer"],
     reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $o, state: "current", reason: ""}]},
    {iteration: 2, small_findings_only: true, classification_head: $o,
     contributing_platforms: ["local-ai-reviewer"],
     reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $o, state: "current", reason: ""}]},
    {iteration: 3, small_findings_only: true, classification_head: $h,
     contributing_platforms: ["local-ai-reviewer"],
     reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]}
  ]
}')"
run_test "1652_s8_stale_stops_count" "1 stale_head" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s8_payload")" "$_sf_head")")"

# --- Scenario 8a: current-round head check ---
run_test "1652_s8a_both_current" "ok" \
  "$(printf '%s\n' "coderabbit" "local-ai-reviewer" | reviewer_loop_current_round_heads_ok "$_sf_head" \
      "coderabbit:$_sf_head" "local-ai-reviewer:$_sf_head" | jq -r '.status')"
run_test "1652_s8a_one_stale" "stale_head" \
  "$(printf '%s\n' "coderabbit" "local-ai-reviewer" | reviewer_loop_current_round_heads_ok "$_sf_head" \
      "coderabbit:$_sf_other" "local-ai-reviewer:$_sf_head" | jq -r '.blocked_by')"
run_test "1652_s8a_one_unknown" "head_unknown" \
  "$(printf '%s\n' "coderabbit" "local-ai-reviewer" | reviewer_loop_current_round_heads_ok "$_sf_head" \
      "local-ai-reviewer:$_sf_head" | jq -r '.blocked_by')"
run_test "1652_s8a_both_stale" "stale_head" \
  "$(printf '%s\n' "coderabbit" "local-ai-reviewer" | reviewer_loop_current_round_heads_ok "$_sf_head" \
      "coderabbit:$_sf_other" "local-ai-reviewer:$_sf_other" | jq -r '.blocked_by')"

# --- Scenario 8b: contributing platforms only ---
_sf_s8b_ok="$(jq -n --arg h "$_sf_head" '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [{iteration: 1, small_findings_only: true, classification_head: $h,
    contributing_platforms: ["local-ai-reviewer", "coderabbit"],
    reviewed_heads: [
      {platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""},
      {platform: "coderabbit", reviewed_head: $h, state: "current", reason: ""},
      {platform: "pr-agent", reviewed_head: "", state: "not-reported", reason: ""}
    ]}]
}')"
run_test "1652_s8b_both_current" "1 exhausted" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s8b_ok")" "$_sf_head")")"
_sf_s8b_stale="$(jq -n --arg h "$_sf_head" --arg o "$_sf_other" '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [{iteration: 1, small_findings_only: true, classification_head: $h,
    contributing_platforms: ["local-ai-reviewer", "coderabbit"],
    reviewed_heads: [
      {platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""},
      {platform: "coderabbit", reviewed_head: $o, state: "not-current", reason: "head_mismatch"}
    ]}]
}')"
run_test "1652_s8b_one_stale" "0 stale_head" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s8b_stale")" "$_sf_head")")"
_sf_s8b_noncontrib="$(jq -n --arg h "$_sf_head" '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [{iteration: 1, small_findings_only: true, classification_head: $h,
    contributing_platforms: ["local-ai-reviewer"],
    reviewed_heads: [
      {platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""},
      {platform: "coderabbit", reviewed_head: "", state: "not-reported", reason: ""}
    ]}]
}')"
run_test "1652_s8b_noncontributor_ignored" "1 exhausted" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s8b_noncontrib")" "$_sf_head")")"
_sf_s8b_absent="$(jq -n --arg h "$_sf_head" '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [{iteration: 1, small_findings_only: true, classification_head: $h,
    reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]}]
}')"
run_test "1652_s8b_absent_contributing" "0 head_unknown" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s8b_absent")" "$_sf_head")")"

# --- Scenario 8c: classification_head, never head_sha ---
_sf_s8c_stale_class="$(jq -n --arg h "$_sf_head" --arg o "$_sf_other" '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [{iteration: 1, small_findings_only: true, head_sha: $h, classification_head: $o,
    contributing_platforms: ["local-ai-reviewer"],
    reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $o, state: "current", reason: ""}]}]
}')"
run_test "1652_s8c_ignores_head_sha_match" "0 stale_head" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s8c_stale_class")" "$_sf_head")")"
_sf_s8c_ok_class="$(jq -n --arg h "$_sf_head" --arg o "$_sf_other" '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [{iteration: 1, small_findings_only: true, head_sha: $o, classification_head: $h,
    contributing_platforms: ["local-ai-reviewer"],
    reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]}]
}')"
run_test "1652_s8c_uses_classification_head" "1 exhausted" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s8c_ok_class")" "$_sf_head")")"

# --- Scenario 9: unknown heads ---
_sf_s9_absent="$(jq -n '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [{iteration: 1, small_findings_only: true,
    contributing_platforms: ["local-ai-reviewer"],
    reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", state: "current", reason: ""}]}]
}')"
run_test "1652_s9_absent_classification" "0 head_unknown" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s9_absent")" "$_sf_head")")"
_sf_s9_empty="$(jq -n --arg h "$_sf_head" '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [{iteration: 1, small_findings_only: true, classification_head: "",
    contributing_platforms: ["local-ai-reviewer"],
    reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]}]
}')"
run_test "1652_s9_empty_classification" "0 head_unknown" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s9_empty")" "$_sf_head")")"
_sf_s9_placeholder="$(jq -n --arg h "$_sf_head" '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [{iteration: 1, small_findings_only: true, classification_head: "unknown-123-1-2",
    contributing_platforms: ["local-ai-reviewer"],
    reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]}]
}')"
run_test "1652_s9_placeholder" "0 head_unknown" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s9_placeholder")" "$_sf_head")")"

# --- Scenario 9a: stop reasons closed set ---
run_test "1652_s9a_exhausted" "exhausted" \
  "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s8b_ok")" "$_sf_head" | jq -r '.stop_reason')"
_sf_s9a_interrupted="$(jq -n --arg h "$_sf_head" '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [
    {iteration: 1, small_findings_only: true, classification_head: $h,
     contributing_platforms: ["local-ai-reviewer"],
     reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]},
    {iteration: 2, small_findings_only: false, classification_head: $h,
     contributing_platforms: ["local-ai-reviewer"],
     reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]},
    {iteration: 3, small_findings_only: true, classification_head: $h,
     contributing_platforms: ["local-ai-reviewer"],
     reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}]}
  ]
}')"
run_test "1652_s9a_not_small" "not_small" \
  "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s9a_interrupted")" "$_sf_head" | jq -r '.stop_reason')"
run_test "1652_s9a_stale" "stale_head" \
  "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s8_payload")" "$_sf_head" | jq -r '.stop_reason')"
run_test "1652_s9a_unknown" "head_unknown" \
  "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s9_placeholder")" "$_sf_head" | jq -r '.stop_reason')"

# --- Scenario 9b: malformed counter output fail-closed ---
run_test "1652_s9b_malformed" "0 head_unknown" \
  "$(reviewer_loop_parse_small_findings_count 'not-json')"
run_test "1652_s9b_missing_field" "0 head_unknown" \
  "$(reviewer_loop_parse_small_findings_count '{"count":2}')"
run_test "1652_s9b_bad_reason" "0 head_unknown" \
  "$(reviewer_loop_parse_small_findings_count '{"count":2,"stop_reason":"nope"}')"

# --- Scenario 10a: within-group precedence ---
_sf_shipped="$(_sf_finding "scripts/development-workflow/pr-review-loop.sh" a "decision matrix")"
_sf_contract="$(_sf_finding "CHANGELOG.md" b "decision matrix")"
run_test "1652_s10a_content_shipped_wins" "shipped_path" \
  "$(printf '%s\n' "$_sf_shipped" "$_sf_contract" | reviewer_loop_small_findings_content_analysis | jq -r '.blocked_by')"
run_test "1652_s10a_content_names_both" "yes" \
  "$(
    j="$(printf '%s\n' "$_sf_shipped" "$_sf_contract" | reviewer_loop_small_findings_content_analysis)"
    sp="$(printf '%s' "$j" | jq -r '.shipped_paths | length')"
    cs="$(printf '%s' "$j" | jq -r '.contract_surfaces | length')"
    if [ "$sp" -ge 1 ] && [ "$cs" -ge 1 ]; then echo yes; else echo "sp=$sp cs=$cs"; fi
  )"
run_test "1652_s10a_currency_stale_wins" "stale_head" \
  "$(printf '%s\n' "coderabbit" "local-ai-reviewer" | reviewer_loop_current_round_heads_ok "$_sf_head" \
      "coderabbit:$_sf_other" | jq -r '.blocked_by')"
run_test "1652_s10a_currency_names_both" "yes" \
  "$(
    j="$(printf '%s\n' "coderabbit" "local-ai-reviewer" | reviewer_loop_current_round_heads_ok "$_sf_head" \
      "coderabbit:$_sf_other")"
    d="$(printf '%s' "$j" | jq -r '.details | join("|")')"
    if [[ "$d" == *stale_head:coderabbit* ]] && [[ "$d" == *head_unknown:local-ai-reviewer* ]]; then echo yes; else echo "$d"; fi
  )"
# Groups mutually exclusive: contract finding means currency never evaluated for blocked_by key
run_test "1652_s10a_groups_exclusive" "contract_surface" \
  "$(printf '%s\n' "$_sf_contract" | reviewer_loop_small_findings_content_analysis | jq -r '.blocked_by')"

# --- Scenario 10b: surface identity print ---
run_test "1652_s10b_identity" "fail_closed_semantics" \
  "$(reviewer_loop_finding_touches_contract_surface "must be fail-closed")"
run_test "1652_s10b_no_match_silent" "" \
  "$(reviewer_loop_finding_touches_contract_surface "trailing whitespace" || true)"
run_test "1652_s10b_first_wins" "acceptance_criteria" \
  "$(reviewer_loop_finding_touches_contract_surface "acceptance criteria and decision matrix both mentioned")"

# --- Scenario 11: BLOCKED_BY values via content analysis / counter ---
run_test "1652_s11_shipped_path" "shipped_path" \
  "$(printf '%s\n' "$_sf_shipped" | reviewer_loop_small_findings_content_analysis | jq -r '.blocked_by')"
run_test "1652_s11_contract_surface" "contract_surface" \
  "$(printf '%s\n' "$_sf_contract" | reviewer_loop_small_findings_content_analysis | jq -r '.blocked_by')"
run_test "1652_s11_stale_head" "stale_head" \
  "$(printf '%s\n' "local-ai-reviewer" | reviewer_loop_current_round_heads_ok "$_sf_head" "local-ai-reviewer:$_sf_other" | jq -r '.blocked_by')"
run_test "1652_s11_head_unknown" "head_unknown" \
  "$(printf '%s\n' "local-ai-reviewer" | reviewer_loop_current_round_heads_ok "$_sf_head" | jq -r '.blocked_by')"
run_test "1652_s11_head_unknown_when_current_missing" "head_unknown" \
  "$(printf '%s\n' "local-ai-reviewer" | reviewer_loop_current_round_heads_ok "" "local-ai-reviewer:$_sf_head" | jq -r '.blocked_by')"
run_test "1652_s11_empty_when_small" "" \
  "$(printf '%s\n' "$_sf_a" | reviewer_loop_small_findings_content_analysis | jq -r '.blocked_by')"

# --- Scenario 14: pre-change ledger without contributing_platforms / head ---
_sf_s14="$(jq -n '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [
    {iteration: 1, small_findings_only: true},
    {iteration: 2, small_findings_only: true}
  ]
}')"
run_test "1652_s14_prechange_ends_run" "0 head_unknown" \
  "$(reviewer_loop_parse_small_findings_count "$(reviewer_loop_small_findings_prior_consecutive_count "$(_sf_ledger "$_sf_s14")" "$_sf_head")")"

# Parser-risk addendum (plan § Parser-risk addendum — one case per edge)
run_test "1652_parser_delegates_not_gate" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "the handler delegates to another module" || echo NONE)"
run_test "1652_parser_microscope" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "look into the microscope carefully" || echo NONE)"
run_test "1652_parser_failXclosed" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "failXclosed is wrong" || echo NONE)"
run_test "1652_parser_allow_list_unhyphenated" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "the allow list is incomplete" || echo NONE)"
run_test "1652_parser_empty_body" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "" || echo NONE)"
run_test "1652_parser_whitespace_only_body" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "   " || echo NONE)"
run_test "1652_parser_case_insensitive" "fail_closed_semantics" \
  "$(reviewer_loop_finding_touches_contract_surface "FAIL-CLOSED required")"
run_test "1652_parser_acceptance_criteria_title_case" "acceptance_criteria" \
  "$(reviewer_loop_finding_touches_contract_surface "Acceptance Criteria AC-3 is missing")"
run_test "1652_parser_code_fence_quoted_term" "decision_gates_and_matrices" \
  "$(reviewer_loop_finding_touches_contract_surface $'```\ndecision gate\n``` is wrong in the spec')"
run_test "1652_parser_listed_phrase_in_url" "decision_gates_and_matrices" \
  "$(reviewer_loop_finding_touches_contract_surface "see https://example.com/decision gate section for details")"
run_test "1652_parser_bare_word_in_url" "NONE" \
  "$(reviewer_loop_finding_touches_contract_surface "see https://example.com/scope/section for context" || echo NONE)"
run_test "1652_parser_quoted_negation_still_matches" "decision_gates_and_matrices" \
  "$(reviewer_loop_finding_touches_contract_surface "this is not a decision gate but the matrix row is wrong")"
run_test "1652_parser_multiline_term_on_last_line" "decision_gates_and_matrices" \
  "$(reviewer_loop_finding_touches_contract_surface $'first line is cosmetic\ndecision matrix row is inconsistent')"

unset _sf_head _sf_other _sf_finding _sf_ledger _sf_is_small
unset _sf_spec _sf_a _sf_b _sf_c _sf_same_cosmetic _sf_same_contract _sf_nl_body
unset _sf_tab_path _sf_tab_body _sf_quote_body _sf_bs_body _sf_plat _sf_raw_out
unset _sf_s8_payload _sf_s8b_ok _sf_s8b_stale _sf_s8b_noncontrib _sf_s8b_absent
unset _sf_s8c_stale_class _sf_s8c_ok_class _sf_s9_absent _sf_s9_empty _sf_s9_placeholder
unset _sf_shipped _sf_contract _sf_s14 _sf_s9a_interrupted _p _ac _pair _word _body



_mc_marker_no_json_body=$'### Automated Reviewer Loop Summary\n<!-- reviewer-loop-history:v1 -->\nNo fenced JSON block here.'
run_test "cycles_entries_count_marker_no_json" "-1 -1 unavailable" \
  "$(reviewer_loop_history_entries_count "$_mc_marker_no_json_body" "run-x")"

# 10 fixer-dispatch-triggering entries (result=needs_fixes), each with a
# DISTINCT head_sha, all recorded under run_id "run-A". Queried with the
# SAME run_id: both lifetime and per-run counts are 10 (at the default
# per-run cap of 10). Queried with a DIFFERENT run_id ("run-B", simulating
# a new orchestration run): lifetime is still 10 (never resets), but the
# per-run count is 0 (fresh run boundary) — this is the core per-run-reset
# proof (AC: "per-run reset across a run boundary").
_mc_ten_dispatch_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [range(1;11) | {iteration: ., head_sha: ("sha-" + (.|tostring)), result: "needs_fixes", run_id: "run-A"}]
}')"
_mc_ten_dispatch_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_mc_ten_dispatch_payload" | jq '.')
\`\`\`"
run_test "cycles_entries_count_same_run_id_counts_both_axes" "10 10 available" \
  "$(reviewer_loop_history_entries_count "$_mc_ten_dispatch_body" "run-A")"
run_test "cycles_entries_count_new_run_id_resets_per_run_only" "10 0 available" \
  "$(reviewer_loop_history_entries_count "$_mc_ten_dispatch_body" "run-B")"

# Mixed-result ledger: 2 needs_fixes + 1 clean + 1 skipped = 4 total entries,
# but only the 2 needs_fixes entries (both run_id "run-A") represent an
# actual fixer dispatch.
_mc_mixed_result_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [
    {iteration: 1, head_sha: "sha-1", result: "needs_fixes", run_id: "run-A"},
    {iteration: 2, head_sha: "sha-1", result: "clean", run_id: "run-A"},
    {iteration: 3, head_sha: "sha-2", result: "skipped", run_id: "run-A"},
    {iteration: 4, head_sha: "sha-3", result: "needs_fixes", run_id: "run-A"}
  ]
}')"
_mc_mixed_result_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_mc_mixed_result_payload" | jq '.')
\`\`\`"
run_test "cycles_entries_count_only_counts_fixer_dispatch_results" "2 2 available" \
  "$(reviewer_loop_history_entries_count "$_mc_mixed_result_body" "run-A")"

# Duplicate-head-sha dedup (still correct on both axes): 3 needs_fixes
# entries under run_id "run-A", 2 of which share the same head_sha (no fix
# actually applied between them). Distinct-head-sha count must be 2, not 3,
# on both the lifetime and per-run axes.
_mc_dup_head_sha_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [
    {iteration: 1, head_sha: "sha-A", result: "needs_fixes", run_id: "run-A"},
    {iteration: 2, head_sha: "sha-A", result: "needs_fixes", run_id: "run-A"},
    {iteration: 3, head_sha: "sha-B", result: "needs_fixes", run_id: "run-A"}
  ]
}')"
_mc_dup_head_sha_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_mc_dup_head_sha_payload" | jq '.')
\`\`\`"
run_test "cycles_entries_count_dedups_duplicate_head_sha" "2 2 available" \
  "$(reviewer_loop_history_entries_count "$_mc_dup_head_sha_body" "run-A")"

# AC / regression (Codex finding on PR #1507): a needs_rerun entry
# IMMEDIATELY FOLLOWED by a needs_fixes entry on the SAME resulting
# head_sha must count as TWO distinct dispatches, not one — deduping by
# head_sha alone would incorrectly merge "PR-Agent's auto-push evaluation
# completed a fix cycle" (needs_rerun) with "a different reviewer found a
# NEW issue on that same resulting state" (needs_fixes), letting more than
# the configured number of real fixes happen before either cap fires.
# Keying on (head_sha, result) instead of head_sha alone fixes this while
# still deduping TRUE duplicates (same head_sha AND same result).
_mc_rerun_then_fixes_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [
    {iteration: 1, head_sha: "H1", result: "needs_rerun", run_id: "run-A"},
    {iteration: 2, head_sha: "H1", result: "needs_fixes", run_id: "run-A"}
  ]
}')"
_mc_rerun_then_fixes_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s
' "$_mc_rerun_then_fixes_payload" | jq '.')
\`\`\`"
run_test "cycles_entries_count_rerun_then_fixes_same_sha_counts_two" "2 2 available" \
  "$(reviewer_loop_history_entries_count "$_mc_rerun_then_fixes_body" "run-A")"

# An entry with an empty/unresolved head_sha must not be counted at all on
# either axis.
_mc_empty_head_sha_payload='{
  "schema": "reviewer_loop_history.v1",
  "history_status": "available",
  "entries": [
    {"iteration": 1, "head_sha": "", "result": "needs_fixes", "run_id": "run-A"},
    {"iteration": 2, "head_sha": "", "result": "needs_fixes", "run_id": "run-A"},
    {"iteration": 3, "head_sha": "sha-C", "result": "needs_fixes", "run_id": "run-A"}
  ]
}'
_mc_empty_head_sha_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_mc_empty_head_sha_payload" | jq '.')
\`\`\`"
run_test "cycles_entries_count_excludes_empty_head_sha" "1 1 available" \
  "$(reviewer_loop_history_entries_count "$_mc_empty_head_sha_body" "run-A")"

# AC: "back-compat entries lacking a run id" — entries written before
# run_id existed (no run_id key at all). They must count toward the
# lifetime axis (real historical fixer dispatches) but can never satisfy
# ANY per-run query, regardless of which run_id is queried — including a
# query with an EMPTY run_id, which must not accidentally match via
# "(.run_id // "") == $runId" both sides being "".
_mc_back_compat_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [range(1;6) | {iteration: ., head_sha: ("sha-old-" + (.|tostring)), result: "needs_fixes"}]
}')"
_mc_back_compat_body="### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_mc_back_compat_payload" | jq '.')
\`\`\`"
run_test "cycles_entries_count_back_compat_counts_lifetime_only" "5 0 available" \
  "$(reviewer_loop_history_entries_count "$_mc_back_compat_body" "run-fresh")"
run_test "cycles_entries_count_back_compat_empty_run_id_query_does_not_match" "5 0 available" \
  "$(reviewer_loop_history_entries_count "$_mc_back_compat_body" "")"

_mc_persisted_unavailable_body=$'### Automated Reviewer Loop Summary\n<!-- reviewer-loop-history:v1 -->\n```json\n{"schema":"reviewer_loop_history.v1","history_status":"unavailable","history_unavailable_reason":"comment_read_failed","entries":[]}\n```\n'
run_test "cycles_entries_count_persisted_unavailable" "-1 -1 unavailable" \
  "$(reviewer_loop_history_entries_count "$_mc_persisted_unavailable_body" "run-x")"

_mc_malformed_body=$'### Automated Reviewer Loop Summary\n<!-- reviewer-loop-history:v1 -->\n```json\n{ not json\n```\n'
run_test "cycles_entries_count_malformed" "-1 -1 unavailable" \
  "$(reviewer_loop_history_entries_count "$_mc_malformed_body" "run-x")"

_mc_wrong_schema_body=$'### Automated Reviewer Loop Summary\n<!-- reviewer-loop-history:v1 -->\n```json\n{"schema":"other.v1","entries":[]}\n```\n'
run_test "cycles_entries_count_wrong_schema" "-1 -1 unavailable" \
  "$(reviewer_loop_history_entries_count "$_mc_wrong_schema_body" "run-x")"

# --- reviewer_loop_resolve_max_cycles (per-run cap) ---
# PR_REVIEW_LOOP_MAX_CYCLES must be unset (not just empty) in this shell for
# the "no override" cases — `env -u` cannot be used here because
# reviewer_loop_resolve_max_cycles is a shell function, not an external
# command, and env only executes external programs.
unset PR_REVIEW_LOOP_MAX_CYCLES

run_test "cycles_resolve_max_default" "10" \
  "$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
run_test "cycles_resolve_max_from_config" "7" \
  "$(reviewer_loop_resolve_max_cycles "7" 2>/dev/null)"
run_test "cycles_resolve_max_env_overrides_config" "3" \
  "$(PR_REVIEW_LOOP_MAX_CYCLES=3 reviewer_loop_resolve_max_cycles "7" 2>/dev/null)"
run_test "cycles_resolve_max_invalid_config_defaults" "10" \
  "$(reviewer_loop_resolve_max_cycles "not-a-number" 2>/dev/null)"
run_test "cycles_resolve_max_invalid_config_warns" "yes" "$(
  # Capture stderr into a variable first, then grep the variable — piping
  # directly into `grep -q` risks a SIGPIPE false-negative under pipefail.
  _mc_warn_stderr="$(reviewer_loop_resolve_max_cycles "not-a-number" 2>&1 >/dev/null)"
  if grep -q "WARN.*not a positive integer" <<< "$_mc_warn_stderr"; then
    echo yes
  else
    echo no
  fi
)"
run_test "cycles_resolve_max_zero_invalid_defaults" "10" \
  "$(PR_REVIEW_LOOP_MAX_CYCLES=0 reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
run_test "cycles_resolve_max_out_of_range_defaults" "10" \
  "$(PR_REVIEW_LOOP_MAX_CYCLES=99999999999999999999 reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
run_test "cycles_resolve_max_six_digit_boundary_accepted" "999999" \
  "$(PR_REVIEW_LOOP_MAX_CYCLES=999999 reviewer_loop_resolve_max_cycles "" 2>/dev/null)"

# --- reviewer_loop_resolve_max_total_cycles (lifetime ceiling) ---
# Mirrors reviewer_loop_resolve_max_cycles's validation exactly (same
# regex, same range), on the sibling env var / config key, default 25.
unset PR_REVIEW_LOOP_MAX_TOTAL_CYCLES

run_test "total_cycles_resolve_max_default" "25" \
  "$(reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
run_test "total_cycles_resolve_max_from_config" "40" \
  "$(reviewer_loop_resolve_max_total_cycles "40" 2>/dev/null)"
run_test "total_cycles_resolve_max_env_overrides_config" "12" \
  "$(PR_REVIEW_LOOP_MAX_TOTAL_CYCLES=12 reviewer_loop_resolve_max_total_cycles "40" 2>/dev/null)"
run_test "total_cycles_resolve_max_invalid_config_defaults" "25" \
  "$(reviewer_loop_resolve_max_total_cycles "not-a-number" 2>/dev/null)"
run_test "total_cycles_resolve_max_invalid_config_warns" "yes" "$(
  _mc_warn_stderr="$(reviewer_loop_resolve_max_total_cycles "not-a-number" 2>&1 >/dev/null)"
  if grep -q "WARN.*not a positive integer" <<< "$_mc_warn_stderr"; then
    echo yes
  else
    echo no
  fi
)"
run_test "total_cycles_resolve_max_zero_invalid_defaults" "25" \
  "$(PR_REVIEW_LOOP_MAX_TOTAL_CYCLES=0 reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
run_test "total_cycles_resolve_max_out_of_range_defaults" "25" \
  "$(PR_REVIEW_LOOP_MAX_TOTAL_CYCLES=99999999999999999999 reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
run_test "total_cycles_resolve_max_six_digit_boundary_accepted" "999999" \
  "$(PR_REVIEW_LOOP_MAX_TOTAL_CYCLES=999999 reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
# The two resolvers must be independently configurable (distinct env vars /
# config keys) — setting one must not affect the other's default.
run_test "cycles_max_cycles_and_max_total_cycles_independent" "10 25" "$(
  unset PR_REVIEW_LOOP_MAX_CYCLES PR_REVIEW_LOOP_MAX_TOTAL_CYCLES
  _m1="$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
  _m2="$(reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
  echo "$_m1 $_m2"
)"

# #1757 (AC-6): the two allowances must resolve fully independently even
# when BOTH resolvers are invoked in the same evaluation with one axis
# omitted/invalid and the other explicitly configured — not just when each
# is tested in isolation as above.
run_test "codex_cap_omit_per_run_keeps_lifetime" "10 40" "$(
  unset PR_REVIEW_LOOP_MAX_CYCLES PR_REVIEW_LOOP_MAX_TOTAL_CYCLES
  _m1="$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
  _m2="$(reviewer_loop_resolve_max_total_cycles "40" 2>/dev/null)"
  echo "$_m1 $_m2"
)"
run_test "codex_cap_omit_lifetime_keeps_per_run" "7 25" "$(
  unset PR_REVIEW_LOOP_MAX_CYCLES PR_REVIEW_LOOP_MAX_TOTAL_CYCLES
  _m1="$(reviewer_loop_resolve_max_cycles "7" 2>/dev/null)"
  _m2="$(reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
  echo "$_m1 $_m2"
)"
run_test "codex_cap_invalid_per_run_keeps_lifetime" "10 40" "$(
  unset PR_REVIEW_LOOP_MAX_CYCLES PR_REVIEW_LOOP_MAX_TOTAL_CYCLES
  _m1="$(reviewer_loop_resolve_max_cycles "not-a-number" 2>/dev/null)"
  _m2="$(reviewer_loop_resolve_max_total_cycles "40" 2>/dev/null)"
  echo "$_m1 $_m2"
)"
run_test "codex_cap_invalid_per_run_keeps_lifetime_warns" "yes" "$(
  unset PR_REVIEW_LOOP_MAX_CYCLES PR_REVIEW_LOOP_MAX_TOTAL_CYCLES
  _mc_warn_stderr="$(reviewer_loop_resolve_max_cycles "not-a-number" 2>&1 >/dev/null)"
  reviewer_loop_resolve_max_total_cycles "40" >/dev/null 2>/dev/null
  if grep -q "WARN.*not a positive integer" <<< "$_mc_warn_stderr"; then
    echo yes
  else
    echo no
  fi
)"
run_test "codex_cap_invalid_lifetime_keeps_per_run" "7 25" "$(
  unset PR_REVIEW_LOOP_MAX_CYCLES PR_REVIEW_LOOP_MAX_TOTAL_CYCLES
  _m1="$(reviewer_loop_resolve_max_cycles "7" 2>/dev/null)"
  _m2="$(reviewer_loop_resolve_max_total_cycles "not-a-number" 2>/dev/null)"
  echo "$_m1 $_m2"
)"
run_test "codex_cap_invalid_lifetime_keeps_per_run_warns" "yes" "$(
  unset PR_REVIEW_LOOP_MAX_CYCLES PR_REVIEW_LOOP_MAX_TOTAL_CYCLES
  reviewer_loop_resolve_max_cycles "7" >/dev/null 2>/dev/null
  _mtc_warn_stderr="$(reviewer_loop_resolve_max_total_cycles "not-a-number" 2>&1 >/dev/null)"
  if grep -q "WARN.*not a positive integer" <<< "$_mtc_warn_stderr"; then
    echo yes
  else
    echo no
  fi
)"

# --- reviewer_loop_cap_exceeded (generic; reused for both axes) ---
# AC: "reaching the cap escalates" / "staying under it does not".

run_test "cycles_cap_under_not_exceeded" "no" \
  "$(reviewer_loop_cap_exceeded 9 10 needs_fixes && echo yes || echo no)"
run_test "cycles_cap_at_limit_exceeded" "yes" \
  "$(reviewer_loop_cap_exceeded 10 10 needs_fixes && echo yes || echo no)"
run_test "cycles_cap_over_limit_exceeded" "yes" \
  "$(reviewer_loop_cap_exceeded 11 10 needs_fixes && echo yes || echo no)"
run_test "cycles_cap_needs_rerun_bounded_by_same_counter" "yes" \
  "$(reviewer_loop_cap_exceeded 10 10 needs_rerun && echo yes || echo no)"
run_test "cycles_cap_clean_never_overridden" "no" \
  "$(reviewer_loop_cap_exceeded 999 10 clean && echo yes || echo no)"
run_test "cycles_cap_already_escalate_not_retriggered" "no" \
  "$(reviewer_loop_cap_exceeded 999 10 escalate && echo yes || echo no)"
run_test "cycles_cap_unknown_count_fails_open" "no" \
  "$(reviewer_loop_cap_exceeded -1 10 needs_fixes && echo yes || echo no)"
# Reused directly against the lifetime axis (default 25) — same function,
# different (count, cap) pair.
run_test "total_cycles_cap_under_not_exceeded" "no" \
  "$(reviewer_loop_cap_exceeded 24 25 needs_fixes && echo yes || echo no)"
run_test "total_cycles_cap_at_limit_exceeded" "yes" \
  "$(reviewer_loop_cap_exceeded 25 25 needs_fixes && echo yes || echo no)"

# #1757 (AC-5): three named cases, since the criterion has three distinct
# outcomes. Per-run axis.
run_test "codex_cap_final_cycle_canonical_clean_ready" "no" \
  "$(reviewer_loop_cap_exceeded 10 10 clean && echo yes || echo no)"
run_test "codex_cap_exhausted_cleared_findings_escalates" "yes" \
  "$(reviewer_loop_cap_exceeded 10 10 waiting_on_reviewer && echo yes || echo no)"
run_test "codex_cap_exhausted_actionable_finding_escalates" "yes" \
  "$(reviewer_loop_cap_exceeded 10 10 needs_fixes && echo yes || echo no)"
# Same three, lifetime axis (default 25) — same function, different pair.
run_test "codex_cap_final_cycle_canonical_clean_ready_lifetime" "no" \
  "$(reviewer_loop_cap_exceeded 25 25 clean && echo yes || echo no)"
run_test "codex_cap_exhausted_cleared_findings_escalates_lifetime" "yes" \
  "$(reviewer_loop_cap_exceeded 25 25 waiting_on_reviewer && echo yes || echo no)"
run_test "codex_cap_exhausted_actionable_finding_escalates_lifetime" "yes" \
  "$(reviewer_loop_cap_exceeded 25 25 needs_fixes && echo yes || echo no)"

# --- reviewer_loop_resolve_cycle_counts (mocked gh) ---

unset MOCK_GH_COMMENTS_OUTPUT MOCK_GH_COMMENTS_EXIT MOCK_GH_EXIT

run_test "cycles_resolve_counts_no_pr_number" "-1 -1" \
  "$(reviewer_loop_resolve_cycle_counts "" "run-x")"

export MOCK_GH_COMMENTS_OUTPUT="[]"
run_test "cycles_resolve_counts_first_run_is_zero_zero" "0 0" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-x" 2>/dev/null)"
unset MOCK_GH_COMMENTS_OUTPUT

# AC / regression (Codex finding on PR #1507): when the OLDEST of two
# summary comments has available history (3 needs_fixes entries) but the
# NEWEST has history_status=unavailable, reviewer_loop_resolve_cycle_counts
# must report "-1 -1" (fail closed on the newest ledger's true status) —
# NOT fall back to the older comment's stale 3/3 count the way the RENDER
# path's reviewer_loop_history_select_summary_record intentionally does.
_mc_stale_available_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1", history_status: "available",
  entries: [range(1;4) | {iteration: ., head_sha: ("sha-" + (.|tostring)), result: "needs_fixes", run_id: "run-A"}]
}')"
_mc_old_comment_body="$(cat <<EOF_OLD_COMMENT
### Automated Reviewer Loop Summary

*Posted automatically by \`pr-review-loop.sh\`.*

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$_mc_stale_available_payload" | jq '.')
\`\`\`
EOF_OLD_COMMENT
)"
_mc_new_comment_body="$(cat <<'EOF_NEW_COMMENT'
### Automated Reviewer Loop Summary

*Posted automatically by `pr-review-loop.sh`.*

<!-- reviewer-loop-history:v1 -->
```json
{"schema":"reviewer_loop_history.v1","history_status":"unavailable","history_unavailable_reason":"comment_read_failed","entries":[]}
```
EOF_NEW_COMMENT
)"
_mc_two_comment_json="$(jq -n \
  --arg oldBody "$_mc_old_comment_body" \
  --arg newBody "$_mc_new_comment_body" \
  '[
    {id: 10, created_at: "2026-08-19T00:00:00Z", body: $oldBody},
    {id: 11, created_at: "2026-08-19T01:00:00Z", body: $newBody}
  ]')"
export MOCK_GH_COMMENTS_OUTPUT="$_mc_two_comment_json"
run_test "cycles_resolve_counts_newest_unavailable_fails_closed_not_stale" "-1 -1" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-A" 2>/dev/null)"
run_test "cycles_end_to_end_newest_unavailable_escalates" "yes" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-A" 2>/dev/null)
  reviewer_loop_cycle_count_unavailable_should_escalate "$_lc" needs_fixes && echo yes || echo no
)"
unset MOCK_GH_COMMENTS_OUTPUT
unset _mc_stale_available_payload _mc_old_comment_body
unset _mc_new_comment_body _mc_two_comment_json

# 10 prior fixer-dispatch entries under run_id "run-A" → resolving with
# run_id "run-A" yields lifetime=10 run=10, matching the default per-run
# cap of 10.
_mc_ten_dispatch_comment_json="$(jq -n --arg body "$_mc_ten_dispatch_body" \
  '[{id: 1, created_at: "2026-08-18T00:00:00Z",
     body: ("### Automated Reviewer Loop Summary\n\n*Posted automatically by `pr-review-loop.sh`.*\n\n" + $body)}]')"
export MOCK_GH_COMMENTS_OUTPUT="$_mc_ten_dispatch_comment_json"
run_test "cycles_resolve_counts_ten_prior_same_run_is_ten_ten" "10 10" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-A" 2>/dev/null)"
# AC: end-to-end — the per-run count against the default cap (10) with a
# needs_fixes verdict must trip max_cycles_exceeded when queried with the
# SAME run_id the entries were recorded under.
run_test "cycles_end_to_end_same_run_reaches_per_run_cap_escalates" "yes" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-A" 2>/dev/null)
  _mx="$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
  reviewer_loop_cap_exceeded "$_rc" "$_mx" needs_fixes && echo yes || echo no
)"

# AC: "per-run reset across a run boundary" — the SAME 10-entry ledger,
# queried with a NEW run_id ("run-B"), must NOT trip the per-run cap
# (fresh run boundary, 0 per-run cycles so far), even though the lifetime
# count (10) is unchanged and would already be visible to the lifetime
# ceiling check.
run_test "cycles_end_to_end_new_run_boundary_does_not_trip_per_run_cap" "no" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-B" 2>/dev/null)
  _mx="$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
  reviewer_loop_cap_exceeded "$_rc" "$_mx" needs_fixes && echo yes || echo no
)"
run_test "cycles_end_to_end_new_run_boundary_lifetime_still_visible" "10" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-B" 2>/dev/null)
  echo "$_lc"
)"
unset MOCK_GH_COMMENTS_OUTPUT

# AC: "lifetime ceiling tripping when no single run reached 10" — three
# separate runs of 9 dispatches each (27 distinct-head-sha entries total,
# each run individually under the per-run cap of 10), queried with a
# brand-new fourth run_id. The per-run count is 0 (new run boundary) and
# does NOT trip max_cycles; the lifetime count is 27, which DOES trip
# max_total_cycles (default 25) — proving the lifetime ceiling catches
# exactly the case a per-run-only cap would miss.
_mc_three_runs_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: (
    [range(1;10) | {iteration: ., head_sha: ("r1-" + (.|tostring)), result: "needs_fixes", run_id: "run-1"}] +
    [range(1;10) | {iteration: ., head_sha: ("r2-" + (.|tostring)), result: "needs_fixes", run_id: "run-2"}] +
    [range(1;10) | {iteration: ., head_sha: ("r3-" + (.|tostring)), result: "needs_fixes", run_id: "run-3"}]
  )
}')"
_mc_three_runs_comment_json="$(jq -n --arg body "$(printf '### Automated Reviewer Loop Summary\n\n*Posted automatically by `pr-review-loop.sh`.*\n\n<!-- reviewer-loop-history:v1 -->\n```json\n%s\n```\n' "$(printf '%s\n' "$_mc_three_runs_payload" | jq '.')")" \
  '[{id: 5, created_at: "2026-08-19T00:00:00Z", body: $body}]')"
export MOCK_GH_COMMENTS_OUTPUT="$_mc_three_runs_comment_json"
run_test "cycles_multi_run_resolve_counts" "27 0" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-4" 2>/dev/null)"
run_test "cycles_multi_run_per_run_cap_not_tripped" "no" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-4" 2>/dev/null)
  _mx="$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
  reviewer_loop_cap_exceeded "$_rc" "$_mx" needs_fixes && echo yes || echo no
)"
run_test "cycles_multi_run_lifetime_ceiling_tripped" "yes" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-4" 2>/dev/null)
  _mtx="$(reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
  reviewer_loop_cap_exceeded "$_lc" "$_mtx" needs_fixes && echo yes || echo no
)"
# AC: "both reasons being distinguishable in output" — the main flow must
# assign two DISTINCT literal REASON strings for the two outcomes (guards
# against a future edit accidentally reusing one string for both, which
# would make the two escalation causes indistinguishable to an operator).
run_test "cycles_reasons_max_cycles_exceeded_present_in_source" "1"   "$(grep -c 'aggregate_reason="max_cycles_exceeded"' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
run_test "cycles_reasons_max_total_cycles_exceeded_present_in_source" "1"   "$(grep -c 'aggregate_reason="max_total_cycles_exceeded"' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
unset MOCK_GH_COMMENTS_OUTPUT

# 3 prior fixer-dispatch entries → both counts 3, well under either
# default cap (10 / 25) → neither is exceeded.
_mc_three_dispatch_payload="$(jq -n '{
  schema: "reviewer_loop_history.v1",
  history_status: "available",
  entries: [range(1;4) | {iteration: ., head_sha: ("sha-" + (.|tostring)), result: "needs_fixes", run_id: "run-C"}]
}')"
_mc_three_dispatch_comment_json="$(jq -n --arg body "$(printf '%s\n' "$_mc_three_dispatch_payload" | jq '.')" \
  '[{id: 2, created_at: "2026-08-18T00:00:00Z",
     body: ("### Automated Reviewer Loop Summary\n\n*Posted automatically by `pr-review-loop.sh`.*\n\n<!-- reviewer-loop-history:v1 -->\n```json\n" + $body + "\n```")}]')"
export MOCK_GH_COMMENTS_OUTPUT="$_mc_three_dispatch_comment_json"
run_test "cycles_resolve_counts_three_prior_same_run_is_three_three" "3 3" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-C" 2>/dev/null)"
run_test "cycles_end_to_end_under_both_caps_does_not_escalate" "no no" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-C" 2>/dev/null)
  _mx="$(reviewer_loop_resolve_max_cycles "" 2>/dev/null)"
  _mtx="$(reviewer_loop_resolve_max_total_cycles "" 2>/dev/null)"
  _per_run="no"; _lifetime="no"
  reviewer_loop_cap_exceeded "$_rc" "$_mx" needs_fixes && _per_run="yes"
  reviewer_loop_cap_exceeded "$_lc" "$_mtx" needs_fixes && _lifetime="yes"
  echo "$_per_run $_lifetime"
)"
unset MOCK_GH_COMMENTS_OUTPUT

# AC: "back-compat entries lacking a run id" (end-to-end via mocked gh) —
# entries with no run_id (as recorded by the pre-dual-cap script version,
# e.g. PR #1507's own cycles 1-5) must not artificially reset OR inflate
# the per-run budget for a fresh run-id-aware invocation.
_mc_back_compat_comment_json="$(jq -n --arg body "$(printf '### Automated Reviewer Loop Summary\n\n*Posted automatically by `pr-review-loop.sh`.*\n\n<!-- reviewer-loop-history:v1 -->\n```json\n%s\n```\n' "$(printf '%s\n' "$_mc_back_compat_payload" | jq '.')")" \
  '[{id: 6, created_at: "2026-08-19T00:00:00Z", body: $body}]')"
export MOCK_GH_COMMENTS_OUTPUT="$_mc_back_compat_comment_json"
run_test "cycles_resolve_counts_back_compat_end_to_end" "5 0" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-fresh" 2>/dev/null)"
unset MOCK_GH_COMMENTS_OUTPUT

# API failure while resolving the ledger (after retries) → -1 -1
# (unavailable). CYCLE_LEDGER_RETRY_WAIT=0 avoids a real sleep between
# retry attempts in the test harness; CYCLE_LEDGER_MAX_RETRIES=1 keeps the
# retry count at its default so the retry path itself is exercised (2
# total attempts).
export MOCK_GH_COMMENTS_EXIT=1
export CYCLE_LEDGER_RETRY_WAIT=0
run_test "cycles_resolve_counts_api_failure_unavailable" "-1 -1" \
  "$(reviewer_loop_resolve_cycle_counts "42" "run-x" 2>/dev/null)"
run_test "cycles_resolve_counts_api_failure_retries_before_giving_up" "yes" "$(
  # Capture stderr into a variable first, then grep the variable — piping
  # directly into `grep -q` risks a SIGPIPE (exit 141) false-negative under
  # `set -o pipefail` if grep exits after its first match while the
  # function is still writing a later WARN line.
  _mc_retry_stderr="$(reviewer_loop_resolve_cycle_counts "42" "run-x" 2>&1 >/dev/null)"
  if grep -q "retrying" <<< "$_mc_retry_stderr"; then
    echo yes
  else
    echo no
  fi
)"
# reviewer_loop_cap_exceeded itself still fails open on an unknown (-1)
# count — it is strictly "is the known count at or past the cap"; the
# fail-closed behavior lives in reviewer_loop_cycle_count_unavailable_
# should_escalate (tested separately below), which the main flow checks
# first.
run_test "cycles_cap_check_still_fails_open_on_unknown_count" "no" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-x" 2>/dev/null)
  reviewer_loop_cap_exceeded "$_rc" 10 needs_fixes && echo yes || echo no
)"
unset MOCK_GH_COMMENTS_EXIT CYCLE_LEDGER_RETRY_WAIT

# --- reviewer_loop_cycle_count_unavailable_should_escalate ---
# Fail-closed safety check: an unreadable cycle ledger must not silently
# disable either cap backstop forever.

run_test "cycles_unavailable_escalates_on_needs_fixes" "yes" \
  "$(reviewer_loop_cycle_count_unavailable_should_escalate -1 needs_fixes && echo yes || echo no)"
run_test "cycles_unavailable_escalates_on_needs_rerun" "yes" \
  "$(reviewer_loop_cycle_count_unavailable_should_escalate -1 needs_rerun && echo yes || echo no)"
run_test "cycles_unavailable_does_not_escalate_on_clean" "no" \
  "$(reviewer_loop_cycle_count_unavailable_should_escalate -1 clean && echo yes || echo no)"
run_test "cycles_unavailable_does_not_escalate_on_already_escalate" "no" \
  "$(reviewer_loop_cycle_count_unavailable_should_escalate -1 escalate && echo yes || echo no)"
run_test "cycles_unavailable_does_not_fire_on_known_count" "no" \
  "$(reviewer_loop_cycle_count_unavailable_should_escalate 3 needs_fixes && echo yes || echo no)"
# AC / regression: end-to-end — an unreadable ledger on a PR with a
# needs_fixes verdict must escalate (fail closed), not silently retry forever.
export MOCK_GH_COMMENTS_EXIT=1
export CYCLE_LEDGER_RETRY_WAIT=0
run_test "cycles_end_to_end_unreadable_ledger_escalates" "yes" "$(
  read -r _lc _rc < <(reviewer_loop_resolve_cycle_counts "42" "run-x" 2>/dev/null)
  reviewer_loop_cycle_count_unavailable_should_escalate "$_lc" needs_fixes && echo yes || echo no
)"
unset MOCK_GH_COMMENTS_EXIT CYCLE_LEDGER_RETRY_WAIT

# --- reviewer_loop_persist_failure_should_escalate ---
# Fail-closed safety check (Codex finding on PR #1507): if this cycle's own
# ledger entry could not be persisted, a dispatch-triggering result must
# not silently let the caller dispatch an uncounted fixer.

run_test "persist_failure_escalates_on_needs_fixes" "yes"   "$(reviewer_loop_persist_failure_should_escalate 1 needs_fixes && echo yes || echo no)"
run_test "persist_failure_escalates_on_needs_rerun" "yes"   "$(reviewer_loop_persist_failure_should_escalate 1 needs_rerun && echo yes || echo no)"
run_test "persist_failure_does_not_escalate_on_clean" "no"   "$(reviewer_loop_persist_failure_should_escalate 1 clean && echo yes || echo no)"
run_test "persist_failure_does_not_escalate_on_already_escalate" "no"   "$(reviewer_loop_persist_failure_should_escalate 1 escalate && echo yes || echo no)"
run_test "persist_failure_does_not_escalate_on_waiting_on_reviewer" "no"   "$(reviewer_loop_persist_failure_should_escalate 1 waiting_on_reviewer && echo yes || echo no)"
run_test "persist_failure_does_not_fire_when_persist_succeeded" "no"   "$(reviewer_loop_persist_failure_should_escalate 0 needs_fixes && echo yes || echo no)"

# --- reviewer_loop_history_build_entry writes run_id from the
#     current_run_id global (same convention already used in that function
#     for unresolved_thread_count/late_thread_count) ---

current_run_id="entry-write-test-run"
unresolved_thread_count=0
late_thread_count=0
pr_number=42
MOCK_GH_HEAD_SHA="entry-write-sha"
MOCK_GH_UPDATED_AT="2026-08-19T00:00:00Z"
export MOCK_GH_HEAD_SHA MOCK_GH_UPDATED_AT
_entry_write_payload="$(reviewer_loop_history_payload_from_existing "" "needs_fixes" "" "bugbot (needs_fixes)" "1" "0")"
run_test "cycles_build_entry_writes_run_id_from_global" "entry-write-test-run" \
  "$(printf '%s\n' "$_entry_write_payload" | jq -r '.entries[0].run_id')"
unset current_run_id unresolved_thread_count late_thread_count pr_number
unset MOCK_GH_HEAD_SHA MOCK_GH_UPDATED_AT

# --- reviewer_loop_history_current_head_sha fallback (Codex finding on
#     PR #1507): a failed/empty HEAD SHA lookup must never silently make an
#     entry uncountable (empty head_sha is excluded from both cap counts by
#     reviewer_loop_history_entries_count). A guaranteed-unique synthetic
#     placeholder keeps the entry countable instead. ---

# shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
pr_number=42
export MOCK_GH_EXIT=1
run_test "cycles_head_sha_fallback_on_lookup_failure_nonempty" "yes" "$(
  _hs="$(reviewer_loop_history_current_head_sha 2>/dev/null)"
  if [ -n "$_hs" ]; then echo yes; else echo no; fi
)"
run_test "cycles_head_sha_fallback_on_lookup_failure_has_prefix" "yes" "$(
  _hs="$(reviewer_loop_history_current_head_sha 2>/dev/null)"
  if [[ "$_hs" == unknown-* ]]; then echo yes; else echo no; fi
)"
run_test "cycles_head_sha_fallback_warns" "yes" "$(
  _stderr="$(reviewer_loop_history_current_head_sha 2>&1 >/dev/null)"
  if printf '%s
' "$_stderr" | grep "WARN.*could not resolve current HEAD SHA" > /dev/null; then
    echo yes
  else
    echo no
  fi
)"
unset MOCK_GH_EXIT

# AC: an entry written via the fallback path must be countable (non-empty
# head_sha), unlike the pre-fix behavior where an empty head_sha silently
# excluded the entry from both cap counts.
# shellcheck disable=SC2034 # read via "${current_run_id:-}" inside
# reviewer_loop_history_build_entry (pr-review-loop.sh), which ShellCheck
# cannot trace across the dynamic HARNESS_MODE=1 source above.
current_run_id="head-sha-fallback-run"
# shellcheck disable=SC2034 # same as current_run_id above.
unresolved_thread_count=0
# shellcheck disable=SC2034 # same as current_run_id above.
late_thread_count=0
export MOCK_GH_EXIT=1
_fallback_entry_payload="$(reviewer_loop_history_payload_from_existing "" "needs_fixes" "" "bugbot (needs_fixes)" "1" "0")"
run_test "cycles_head_sha_fallback_entry_has_nonempty_head_sha" "yes" "$(
  _entry_hs="$(printf '%s
' "$_fallback_entry_payload" | jq -r '.entries[0].head_sha')"
  if [ -n "$_entry_hs" ]; then echo yes; else echo no; fi
)"
unset MOCK_GH_EXIT current_run_id unresolved_thread_count late_thread_count pr_number
unset _fallback_entry_payload

# --- Regression guard (Codex finding on PR #1507): the max_cycles cap
# override in the main flow MUST run before the compare-mode metrics-row
# append. --compare mode's own contract is "the overall exit code and
# RESULT are identical to what normal mode would produce" — the overrides
# are unconditional (they also apply in --compare mode), so if the metrics
# row were appended first, docs/workflow/retro-metrics-platforms.md would
# record a stale pre-cap value while the script's own final RESULT/summary
# say escalate, corrupting reviewer-graduation comparison data. This is a
# source-ordering check (the runtime behavior requires a full --compare-
# mode platform run to exercise, which is out of scope for this harness)
# but it directly guards against the exact regression found.
_mc_cap_line="$(grep -n 'reviewer_loop_cap_exceeded "\$cycle_count" "\$max_cycles" "\$aggregate_result"' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
_mc_metrics_line="$(grep -n 'append_compare_metrics_row "\${_metrics_args\[@\]}"' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
if [ -n "$_mc_cap_line" ] && [ -n "$_mc_metrics_line" ] \
    && [ "$_mc_cap_line" -lt "$_mc_metrics_line" ]; then
  run_test "cycles_cap_override_precedes_compare_metrics_append" "yes" "yes"
else
  run_test "cycles_cap_override_precedes_compare_metrics_append" "yes" "no"
fi
unset _mc_cap_line _mc_metrics_line

# --- Single-RESULT-line fix (Codex finding on PR #1507: "emit only the
#     corrected reviewer-loop result") ---
#
# The script's own kv_value helper (used elsewhere in this same script to
# parse a sub-invocation's key=value output) returns the FIRST matching
# key, not the last (`{ ...; print; exit }` on first match) — so printing
# RESULT= twice (an initial value, then a "corrected" one after a
# persistence failure) would be silently invisible to any caller using
# that same convention, which would still see the stale first value despite
# the script exiting escalated. The fix restructures the tail of the main
# flow so _post_review_summary (and its ledger_persist_failed correction)
# runs BEFORE the single RESULT=/REASON= print, not after — replacing the
# earlier "supplementary corrected compare-metrics row" workaround (now
# unnecessary: the main compare-metrics append also moved after
# persistence, so it always reflects the single final result too).
#
# This is a source-ordering check (the runtime behavior requires a full
# needs_fixes-with-persistence-failure platform run to exercise end to end,
# which is out of scope for this harness) but it directly guards against
# the exact regression found: _post_review_summary's call site must appear
# BEFORE print_kv RESULT "$aggregate_result" in the tail of the script.
_post_summary_call_line="$(grep -n '_post_review_summary "\$aggregate_result" "\$aggregate_reason"'   "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null   | head -1 | cut -d: -f1)"
_print_result_line="$(grep -n 'print_kv RESULT "\$aggregate_result"'   "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null   | head -1 | cut -d: -f1)"
if [ -n "$_post_summary_call_line" ] && [ -n "$_print_result_line" ]     && [ "$_post_summary_call_line" -lt "$_print_result_line" ]; then
  run_test "persist_and_correction_precede_single_result_print" "yes" "yes"
else
  run_test "persist_and_correction_precede_single_result_print" "yes" "no"
fi
# Only ONE call site for `print_kv RESULT "$aggregate_result"` should exist
# in the whole script — a second, differently-worded RESULT print (e.g.
# `print_kv RESULT escalate`) reintroducing the two-line bug would not be
# caught by the check above alone.
run_test "only_one_print_kv_result_aggregate_result_call_site" "1"   "$(grep -c 'print_kv RESULT "\$aggregate_result"' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
unset _post_summary_call_line _print_result_line

# Function-ordering check (mirrors Area 11's Test 11.6) — the max_cycles /
# max_total_cycles enforcement functions must stay callable from the
# harness after future refactors move code around.
for _mc_fn in reviewer_loop_resolve_run_id reviewer_loop_history_entries_count \
    reviewer_loop_resolve_max_cycles reviewer_loop_resolve_max_total_cycles \
    reviewer_loop_cap_exceeded reviewer_loop_cycle_count_unavailable_should_escalate \
    reviewer_loop_persist_failure_should_escalate \
    reviewer_loop_history_current_head_sha \
    reviewer_loop_resolve_cycle_counts; do
  _mc_fn_line="$(grep -n "^${_mc_fn}()" \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
    | head -1 | cut -d: -f1)"
  _mc_harness_return_line="$(grep -n '_HARNESS_MODE_EFFECTIVE.*return 0' \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
    | head -1 | cut -d: -f1)"
  if [ -n "$_mc_fn_line" ] && [ -n "$_mc_harness_return_line" ] \
      && [ "$_mc_fn_line" -lt "$_mc_harness_return_line" ]; then
    run_test "cycles_fn_defined_before_harness_return_${_mc_fn}" "yes" "yes"
  else
    run_test "cycles_fn_defined_before_harness_return_${_mc_fn}" "yes" "no"
  fi
done
# #1657 moved the history selector to workflow-lib.sh; keep a source-order check here.
for _mc_fn in reviewer_loop_history_select_latest_summary_record \
    reviewer_loop_history_extract_latest_json; do
  _mc_fn_line="$(grep -n "^${_mc_fn}()" \
    "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" 2>/dev/null \
    | head -1 | cut -d: -f1)"
  if [ -n "$_mc_fn_line" ]; then
    run_test "history_fn_defined_in_workflow_lib_${_mc_fn}" "yes" "yes"
  else
    run_test "history_fn_defined_in_workflow_lib_${_mc_fn}" "yes" "no"
  fi
done
unset _mc_fn _mc_fn_line _mc_harness_return_line

unset _mc_no_marker_body _mc_marker_no_json_body
unset _mc_ten_dispatch_payload _mc_ten_dispatch_body _mc_ten_dispatch_comment_json
unset _mc_mixed_result_payload _mc_mixed_result_body
unset _mc_dup_head_sha_payload _mc_dup_head_sha_body
unset _mc_rerun_then_fixes_payload _mc_rerun_then_fixes_body
unset _mc_empty_head_sha_payload _mc_empty_head_sha_body
unset _mc_back_compat_payload _mc_back_compat_body _mc_back_compat_comment_json
unset _mc_persisted_unavailable_body _mc_malformed_body _mc_wrong_schema_body
unset _mc_three_dispatch_payload _mc_three_dispatch_comment_json
unset _mc_three_runs_payload _mc_three_runs_comment_json
unset _entry_write_payload

# Area 11: Step 7b regression-label auto-restore (Option C, issue #805)
#
# restore_regression_label_if_missing() is defined before the HARNESS_MODE
# return point and is therefore callable directly from the test harness.
# These tests exercise the actual function (not source-string grep) so that
# runtime regressions — e.g. a mis-scoped case branch, a missing label
# check, or a silent gh failure — are detected.
#
# The mock gh stub (already on PATH) is driven by:
#   MOCK_GH_OUTPUT       — `gh pr view` label-check result ("true"/"false")
#   MOCK_GH_COMMENTS_OUTPUT — `gh api .../comments` result (JSON array; controls
#                             summary-comment gate)
#   MOCK_GH_CALL_LOG     — records every `gh pr edit --add-label` call
#   MOCK_GH_EXIT         — controls whether gh exits with an error (all calls)
#   MOCK_GH_COMMENTS_EXIT — controls whether the comments API call exits with
#                           an error independently of MOCK_GH_EXIT
#
# Summary-comment gate:
#   label missing + latest summary clean/skipped for current head → restore IS called
#   label missing + latest summary absent/stale/non-clean         → restore NOT called
#   comments API fails                                            → fail-open: restore IS called + WARN emitted
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 11: regression-label auto-restore (Option C, issue #805) ==="

# Reset mock vars from earlier areas.
unset MOCK_GH_POST_EXIT MOCK_GH_POST_OUTPUT MOCK_GH_CALL_LOG MOCK_GH_EXIT
unset MOCK_GH_COMMENTS_OUTPUT MOCK_GH_COMMENTS_EXIT MOCK_GH_HEAD_SHA

_SUMMARY_CURRENT_HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
_SUMMARY_OLD_HEAD_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

_summary_comment_json_for_11() {
  local _head_sha="$1"
  local _result="$2"
  local _created_at="${3:-2026-08-26T12:00:00Z}"
  local _payload
  local _body

  _payload="$(jq -n \
    --arg headSha "$_head_sha" \
    --arg result "$_result" \
    '{
      schema: "reviewer_loop_history.v1",
      history_status: "available",
      entries: [{iteration: 1, head_sha: $headSha, result: $result}]
    }')"
  _body="$(printf '### Automated Reviewer Loop Summary\n\n*Posted automatically by `pr-review-loop.sh`.*\n\n<!-- reviewer-loop-history:v1 -->\n```json\n%s\n```\n' "$_payload")"
  jq -n --arg body "$_body" --arg createdAt "$_created_at" \
    '[{id: 1, created_at: $createdAt, body: $body}]'
}

# JSON payload used by tests that require a current-head clean summary.
_SUMMARY_COMMENT_JSON="$(_summary_comment_json_for_11 "$_SUMMARY_CURRENT_HEAD_SHA" "clean")"
_SUMMARY_STALE_COMMENT_JSON="$(_summary_comment_json_for_11 "$_SUMMARY_OLD_HEAD_SHA" "clean")"
_SUMMARY_NEEDS_FIXES_COMMENT_JSON="$(_summary_comment_json_for_11 "$_SUMMARY_CURRENT_HEAD_SHA" "needs_fixes")"

# Test 11.1: label absent + latest summary clean for the current PR head on an
# implementation branch → gh pr edit IS called.
if ! _call_log_11="$(mktemp)"; then
  echo "ERROR: failed to allocate regression-label test temp file" >&2
  exit 1
fi
export MOCK_GH_OUTPUT="false"
export MOCK_GH_HEAD_SHA="$_SUMMARY_CURRENT_HEAD_SHA"
export MOCK_GH_COMMENTS_OUTPUT="$_SUMMARY_COMMENT_JSON"
export MOCK_GH_CALL_LOG="$_call_log_11"
export MOCK_GH_OWNERSHIP_BRANCH="fix/42-my-fix"
restore_regression_label_if_missing "42" "fix/42-my-fix" 2>/dev/null
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_absent_current_head_clean_summary_calls_gh_edit" "1" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_COMMENTS_OUTPUT MOCK_GH_HEAD_SHA MOCK_GH_OWNERSHIP_BRANCH

# Test 11.2: label already present on an implementation branch → the helper is
# still invoked (revalidate-or-remove, PR #1818 F1 round 10): an already-present
# label is not proof it is current, so the restore path routes it through
# apply-readiness-labels.sh. The stub helper reaches the post-apply verification
# with stub JSON and escalates (label-verify-failed); the WARN-and-proceed
# branch keeps the function returning 0.
if ! _call_log_11="$(mktemp)"; then
  echo "ERROR: failed to allocate regression-label test temp file" >&2
  exit 1
fi
export MOCK_GH_OUTPUT="true"
export MOCK_GH_CALL_LOG="$_call_log_11"
_rfr_present_exit=0
restore_regression_label_if_missing "42" "feature/42-my-feature" 2>/dev/null || _rfr_present_exit=$?
run_test "restore_label_already_present_returns_0" "0" "$_rfr_present_exit"
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_already_present_no_gh_edit" "0" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG _rfr_present_exit

# Test 11.3: non-implementation branch (spec/) → NO gh pr edit regardless of
# label state or summary-comment presence.
if ! _call_log_11="$(mktemp)"; then
  echo "ERROR: failed to allocate regression-label test temp file" >&2
  exit 1
fi
export MOCK_GH_OUTPUT="false"
export MOCK_GH_COMMENTS_OUTPUT="$_SUMMARY_COMMENT_JSON"
export MOCK_GH_CALL_LOG="$_call_log_11"
restore_regression_label_if_missing "42" "spec/42-my-spec" 2>/dev/null
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_non_impl_branch_no_gh_edit" "0" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_COMMENTS_OUTPUT

# Test 11.4: gh pr view failure (API error) → function returns 0 (fail-open),
# gh pr edit is NOT called (no false re-apply on unknown label state).
# Note: MOCK_GH_EXIT=1 affects the label-check `gh pr view` call; the function
# returns early before reaching the summary-comment gate.
if ! _call_log_11="$(mktemp)"; then
  echo "ERROR: failed to allocate regression-label test temp file" >&2
  exit 1
fi
export MOCK_GH_EXIT=1
export MOCK_GH_CALL_LOG="$_call_log_11"
_restore_exit=0
restore_regression_label_if_missing "42" "fix/42-api-fail" 2>/dev/null || _restore_exit=$?
run_test "restore_label_gh_view_fail_returns_0" "0" "$_restore_exit"
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_gh_view_fail_no_gh_edit" "0" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_EXIT

# Test 11.5: hotfix/* branch + label absent + summary comment PRESENT
# → gh pr edit called (hotfix is an implementation branch; must be in scope).
if ! _call_log_11="$(mktemp)"; then
  echo "ERROR: failed to allocate regression-label test temp file" >&2
  exit 1
fi
export MOCK_GH_OUTPUT="false"
export MOCK_GH_HEAD_SHA="$_SUMMARY_CURRENT_HEAD_SHA"
export MOCK_GH_COMMENTS_OUTPUT="$_SUMMARY_COMMENT_JSON"
export MOCK_GH_CALL_LOG="$_call_log_11"
export MOCK_GH_OWNERSHIP_BRANCH="hotfix/99-critical"
restore_regression_label_if_missing "99" "hotfix/99-critical" 2>/dev/null
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_hotfix_branch_calls_gh_edit" "1" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_COMMENTS_OUTPUT MOCK_GH_HEAD_SHA MOCK_GH_OWNERSHIP_BRANCH

# Test 11.6: restore function is defined before the HARNESS_MODE return point
# (source-level ordering check — ensures the function remains testable after
# future refactors move it).
_restore_fn_line="$(grep -n 'restore_regression_label_if_missing()' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
_harness_return_line="$(grep -n '_HARNESS_MODE_EFFECTIVE.*return 0' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
if [ -n "$_restore_fn_line" ] && [ -n "$_harness_return_line" ] \
    && [ "$_restore_fn_line" -lt "$_harness_return_line" ]; then
  _fn_ordering_ok="yes"
else
  _fn_ordering_ok="no"
fi
run_test "restore_fn_defined_before_harness_return" "yes" "$_fn_ordering_ok"
unset _restore_fn_line _harness_return_line _fn_ordering_ok

# Test 11.7: label absent + summary comment ABSENT → gh pr edit NOT called.
# This is the normal initial state (loop has never run) or the window in which
# a human intentional removal is unambiguous. The restore must be suppressed.
_call_log_11="$(mktemp)"
export MOCK_GH_OUTPUT="false"
export MOCK_GH_HEAD_SHA="$_SUMMARY_CURRENT_HEAD_SHA"
export MOCK_GH_COMMENTS_OUTPUT="[]"
export MOCK_GH_CALL_LOG="$_call_log_11"
restore_regression_label_if_missing "42" "fix/42-no-summary" 2>/dev/null
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_absent_summary_absent_no_gh_edit" "0" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_COMMENTS_OUTPUT MOCK_GH_HEAD_SHA

# Test 11.8: label absent + stale clean summary from an older head → gh pr edit
# is NOT called. This is the regression where ready-for-regression could be
# resurrected before reviewer findings were clean for the new push.
_call_log_11="$(mktemp)"
export MOCK_GH_OUTPUT="false"
export MOCK_GH_HEAD_SHA="$_SUMMARY_CURRENT_HEAD_SHA"
export MOCK_GH_COMMENTS_OUTPUT="$_SUMMARY_STALE_COMMENT_JSON"
export MOCK_GH_CALL_LOG="$_call_log_11"
restore_regression_label_if_missing "42" "fix/42-stale-summary" 2>/dev/null
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_stale_clean_summary_no_gh_edit" "0" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_COMMENTS_OUTPUT MOCK_GH_HEAD_SHA

# Test 11.9: label absent + latest current-head summary is not clean/skipped
# → gh pr edit is NOT called.
_call_log_11="$(mktemp)"
export MOCK_GH_OUTPUT="false"
export MOCK_GH_HEAD_SHA="$_SUMMARY_CURRENT_HEAD_SHA"
export MOCK_GH_COMMENTS_OUTPUT="$_SUMMARY_NEEDS_FIXES_COMMENT_JSON"
export MOCK_GH_CALL_LOG="$_call_log_11"
restore_regression_label_if_missing "42" "fix/42-needs-fixes" 2>/dev/null
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_current_head_needs_fixes_summary_no_gh_edit" "0" "$_edit_calls"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_COMMENTS_OUTPUT MOCK_GH_HEAD_SHA

# Test 11.10: label absent + comments API failure → fail-open: gh pr edit IS called
# and a WARN is emitted. Rationale: the #805 regression (label silently dropped
# after loop ran) is the higher-frequency real-world failure; when we cannot
# determine whether the loop ran, restoring is the safer choice.
_call_log_11="$(mktemp)"
export MOCK_GH_OUTPUT="false"
export MOCK_GH_HEAD_SHA="$_SUMMARY_CURRENT_HEAD_SHA"
export MOCK_GH_COMMENTS_EXIT=1
export MOCK_GH_CALL_LOG="$_call_log_11"
export MOCK_GH_OWNERSHIP_BRANCH="fix/42-comments-fail"
_warn_output="$(restore_regression_label_if_missing "42" "fix/42-comments-fail" 2>&1)"
_edit_calls="$(grep -c -- '--add-label' "$_call_log_11" 2>/dev/null)" || _edit_calls="0"
run_test "restore_label_comments_api_fail_failopen_calls_gh_edit" "1" "$_edit_calls"
# Verify WARN is emitted (not silent).
if grep -q "WARN" <<< "$_warn_output"; then
  _warn_emitted="yes"
else
  _warn_emitted="no"
fi
run_test "restore_label_comments_api_fail_warn_emitted" "yes" "$_warn_emitted"
if grep -q "summary-comment lookup failed; fail-open restore" <<< "$_warn_output" \
    && ! grep -q "current-head clean reviewer-loop summary found" <<< "$_warn_output"; then
  _failopen_reason_ok="yes"
else
  _failopen_reason_ok="no"
fi
run_test "restore_label_comments_api_fail_logs_failopen_reason" "yes" "$_failopen_reason_ok"
rm -f "$_call_log_11"
unset MOCK_GH_CALL_LOG MOCK_GH_COMMENTS_EXIT MOCK_GH_HEAD_SHA MOCK_GH_OWNERSHIP_BRANCH _warn_output _failopen_reason_ok

# Reset mock state.
export MOCK_GH_OUTPUT='[]'
unset MOCK_GH_EXIT MOCK_GH_COMMENTS_OUTPUT MOCK_GH_COMMENTS_EXIT MOCK_GH_HEAD_SHA
unset _SUMMARY_COMMENT_JSON _SUMMARY_STALE_COMMENT_JSON _SUMMARY_NEEDS_FIXES_COMMENT_JSON
unset _SUMMARY_CURRENT_HEAD_SHA _SUMMARY_OLD_HEAD_SHA

# Test 11.11 (PR #1818 finding, #1408 round 2): the restore path must route the
# label mutation through apply-readiness-labels.sh, not a bare
# `gh pr edit --add-label ready-for-regression` — the direct apply bypassed the
# reviewer/CI verdict gate this helper exists to enforce. The gh stub cannot
# exercise the helper's own gating (it is covered by
# test-apply-readiness-labels.sh), so this is a source-level check: the restore
# function invokes the helper, and no direct `--add-label "ready-for-regression"`
# remains anywhere in pr-review-loop.sh.
_loop_src="$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
_helper_calls="$(grep -c 'apply-readiness-labels.sh' "$_loop_src" 2>/dev/null)" || _helper_calls="0"
run_test "restore_path_invokes_readiness_helper" "yes" \
  "$([ "$_helper_calls" -ge 1 ] && grep -q 'apply-readiness-labels.sh' \
      <(sed -n '/restore_regression_label_if_missing()/,/^}/p' "$_loop_src") && echo yes || echo no)"
_direct_applies="$(grep -c -- '--add-label "ready-for-regression"' "$_loop_src" 2>/dev/null)" || _direct_applies="0"
run_test "no_direct_ready_for_regression_apply_in_loop" "0" "$_direct_applies"
# Test 11.13 (PR #1818 finding 3, round 4): the restore path must not
# discard the helper's stderr — its WARN output (e.g. the head-drift
# "label remains attached, remove manually" warning) is the actionable
# signal for whoever is watching the loop. The helper invocation spans
# two source lines, so flatten the restore function body to one line
# before checking for a stderr redirection on it.
_restore_flat="$(sed -n '/restore_regression_label_if_missing()/,/^}/p' "$_loop_src" | tr '\n' ' ' | tr -s ' ')"
_helper_stderr_redirs="$(printf '%s\n' "$_restore_flat" | grep -c 'apply-readiness-labels\.sh[^;]*2>/dev/null' || true)"
run_test "restore_path_does_not_discard_helper_stderr" "0" "$_helper_stderr_redirs"
unset _restore_flat _helper_stderr_redirs
# Test 11.12 (PR #1818 finding, #1408 round 3): the clean-path Step 7b summary
# must instruct agents to route the label through the helper too, not hand
# them a copy-paste `gh pr edit --add-label` command that bypasses the gate
# (the second emission site, in the summary-comment section).
_summary_uses_helper="$(sed -n '/Step 7b regression-label assertion/,/^  fi$/p' "$_loop_src" \
  | grep -c 'apply-readiness-labels.sh' 2>/dev/null)" || _summary_uses_helper="0"
run_test "step7b_summary_uses_readiness_helper" "1" \
  "$([ "$_summary_uses_helper" -ge 1 ] && echo 1 || echo 0)"
# Test 11.14 (PR #1818 F1 round 10): Protocol 91 Step 8a Check 4 must invoke
# the helper for BOTH label-present and label-absent PRs — the previous
# label-present skip left a stale 'ready-for-human-review' on the PR after a
# same-SHA reviewer rerun failed without adding a thread, exactly the case the
# helper's label_initially_present revalidate-or-remove was built for. The
# checklist is a fenced bash block, so this is a source-level assertion.
_p91="$REPO_ROOT/docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"
_check4="$(awk '/^# Check 4:/{f=1} f{print} f && /^echo "✅ Label readiness checklist passed/{exit}' "$_p91")"
run_test "step8a_check4_has_no_label_present_skip" "0" \
  "$(printf '%s\n' "$_check4" | grep -c 'Skipping re-application' || true)"
run_test "step8a_check4_runs_helper_unconditionally" "1" \
  "$([ "$(printf '%s\n' "$_check4" | grep -c 'apply-readiness-labels.sh' || true)" -ge 1 ] \
      && grep -q 'if ! \./scripts/development-workflow/apply-readiness-labels.sh' <<< "$_check4" \
      && echo 1 || echo 0)"
# Test 11.15 (PR #1818 F1 round 10): the restore path's label-present branch
# must also invoke the helper (no skip when 'ready-for-regression' is already
# present) — the same stale-label hazard as Check 4.
run_test "restore_path_revalidates_present_label_via_helper" "1" \
  "$(sed -n '/restore_regression_label_if_missing()/,/^}/p' "$_loop_src" | grep -c 'revalidating through apply-readiness-labels.sh' || true)"
# Test 11.16 (PR #1818 F2 round 10): Protocol 05 §7.3 must route the release
# PR's 'ready-for-regression' label through the helper — the previous direct
# `gh pr edit <pr_number> --add-label "ready-for-regression"` exemption
# bypassed the CI-leg gate even though the helper classifies release/* heads
# as non-implementation (no reviewer leg) and never refuses for that reason.
_p05="$REPO_ROOT/docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md"
run_test "protocol05_regression_label_uses_helper" "1" \
  "$([ "$(grep -c 'apply-readiness-labels.sh' "$_p05" || true)" -ge 1 ] && echo 1 || echo 0)"
run_test "protocol05_has_no_direct_ready_for_regression_apply" "0" \
  "$(grep -c -- '--add-label "ready-for-regression"' "$_p05" || true)"
unset _loop_src _helper_calls _direct_applies _summary_uses_helper _p91 _check4 _p05

# ---------------------------------------------------------------------------
# Area 12: reviewer-failed label sync (issue #804)
#
# reviewer_failed_label_required_for_result(), ensure_reviewer_failed_label_exists(),
# and sync_reviewer_failed_label() are defined before the HARNESS_MODE return point
# and are therefore callable directly from the test harness.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 12: reviewer-failed label sync (issue #804) ==="

_reviewer_failed_required() {
  if reviewer_failed_label_required_for_result "$1" "${2:-}"; then
    printf 'yes'
  else
    printf 'no'
  fi
}

# #1789: an expired wait is no longer reported as escalate/timeout; the escalate
# rule is exercised with a failure-only reason instead.
run_test "reviewer_failed_escalate_run_failed" "yes" "$(_reviewer_failed_required escalate claude_code_action_run_failed)"
run_test "reviewer_failed_escalate_empty_reason" "yes" "$(_reviewer_failed_required escalate '')"
run_test "reviewer_failed_escalate_pending_timeout" "yes" "$(_reviewer_failed_required escalate pending_timeout)"
run_test "reviewer_failed_skipped_unavailable" "yes" "$(_reviewer_failed_required skipped unavailable)"
run_test "reviewer_failed_skipped_thread_check_failed" "yes" "$(_reviewer_failed_required skipped thread-check-failed)"
run_test "reviewer_failed_skipped_not_configured" "no" "$(_reviewer_failed_required skipped not_configured)"
run_test "reviewer_failed_skipped_file_limit" "no" "$(_reviewer_failed_required skipped analysis_skipped_file_limit)"
run_test "reviewer_failed_clean_no" "no" "$(_reviewer_failed_required clean timeout)"
run_test "reviewer_failed_needs_fixes_no" "no" "$(_reviewer_failed_required needs_fixes '')"
run_test "reviewer_failed_needs_rerun_no" "no" "$(_reviewer_failed_required needs_rerun '')"
run_test "reviewer_failed_waiting_on_reviewer_no" "no" "$(_reviewer_failed_required waiting_on_reviewer codex-github-review-pending)"

_waiting_case_source="$(awk '
  /case "\\$platform_result" in/ {capture=1}
  capture {print}
  /^  esac$/ && capture {exit}
' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
if grep -q 'needs_fixes|waiting_on_reviewer|escalate' <<< "$_waiting_case_source"; then
  _waiting_folded_into_blocker="yes"
else
  _waiting_folded_into_blocker="no"
fi
run_test "waiting_on_reviewer_not_folded_into_blocker_arm" "no" "$_waiting_folded_into_blocker"
unset _waiting_case_source _waiting_folded_into_blocker

_rf_accumulated=0
if reviewer_failed_label_required_for_result clean ""; then
  _rf_accumulated=1
fi
if reviewer_failed_label_required_for_result skipped unavailable; then
  _rf_accumulated=1
fi
if reviewer_failed_label_required_for_result clean ""; then
  _rf_accumulated=1
fi
run_test "reviewer_failed_accumulator_or" "1" "$_rf_accumulated"
unset _rf_accumulated

unset MOCK_GH_CALL_LOG MOCK_GH_EXIT MOCK_GH_LABEL_VIEW_EXIT MOCK_GH_LABEL_CREATE_EXIT MOCK_GH_PR_EDIT_EXIT

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
export MOCK_GH_LABEL_VIEW_EXIT=1
sync_reviewer_failed_label "42" "1" 2>/dev/null
_create_calls="$(grep -c -- 'label create reviewer-failed' "$_call_log_12" 2>/dev/null)" || _create_calls="0"
_add_calls="$(grep -c -- 'pr edit 42 --add-label reviewer-failed' "$_call_log_12" 2>/dev/null)" || _add_calls="0"
run_test "reviewer_failed_required_creates_missing_label" "1" "$_create_calls"
run_test "reviewer_failed_required_adds_label" "1" "$_add_calls"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG MOCK_GH_LABEL_VIEW_EXIT

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
export MOCK_GH_LABEL_VIEW_EXIT=0
sync_reviewer_failed_label "42" "1" 2>/dev/null
_create_calls="$(grep -c -- 'label create reviewer-failed' "$_call_log_12" 2>/dev/null)" || _create_calls="0"
_add_calls="$(grep -c -- 'pr edit 42 --add-label reviewer-failed' "$_call_log_12" 2>/dev/null)" || _add_calls="0"
run_test "reviewer_failed_existing_label_no_create" "0" "$_create_calls"
run_test "reviewer_failed_existing_label_adds_label" "1" "$_add_calls"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG MOCK_GH_LABEL_VIEW_EXIT

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
export MOCK_GH_OUTPUT='reviewer-failed'
sync_reviewer_failed_label "42" "0" 2>/dev/null
_remove_calls="$(grep -c -- 'pr edit 42 --remove-label reviewer-failed' "$_call_log_12" 2>/dev/null)" || _remove_calls="0"
run_test "reviewer_failed_not_required_removes_present_label" "1" "$_remove_calls"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG MOCK_GH_OUTPUT

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
export MOCK_GH_OUTPUT='some-other-label'
sync_reviewer_failed_label "42" "0" 2>/dev/null
_remove_calls="$(grep -c -- 'pr edit 42 --remove-label reviewer-failed' "$_call_log_12" 2>/dev/null)" || _remove_calls="0"
run_test "reviewer_failed_not_required_absent_noop" "0" "$_remove_calls"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG MOCK_GH_OUTPUT

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
export MOCK_GH_EXIT=1
export MOCK_GH_PR_EDIT_EXIT=0
sync_reviewer_failed_label "42" "0" 2>/dev/null
_remove_calls="$(grep -c -- 'pr edit 42 --remove-label reviewer-failed' "$_call_log_12" 2>/dev/null)" || _remove_calls="0"
run_test "reviewer_failed_not_required_view_failure_attempts_remove" "1" "$_remove_calls"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG MOCK_GH_EXIT MOCK_GH_PR_EDIT_EXIT

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
export MOCK_GH_LABEL_VIEW_EXIT=1
export MOCK_GH_LABEL_CREATE_EXIT=1
_sync_exit=0
_warn_output="$(sync_reviewer_failed_label "42" "1" 2>&1)" || _sync_exit=$?
_add_calls="$(grep -c -- 'pr edit 42 --add-label reviewer-failed' "$_call_log_12" 2>/dev/null)" || _add_calls="0"
run_test "reviewer_failed_create_failure_returns_0" "0" "$_sync_exit"
run_test "reviewer_failed_create_failure_still_attempts_add" "1" "$_add_calls"
if grep -q "WARN" <<< "$_warn_output"; then
  _warn_emitted="yes"
else
  _warn_emitted="no"
fi
run_test "reviewer_failed_create_failure_warns" "yes" "$_warn_emitted"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG MOCK_GH_LABEL_VIEW_EXIT MOCK_GH_LABEL_CREATE_EXIT _warn_output _sync_exit

_call_log_12="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log_12"
sync_reviewer_failed_label "42" "1" 2>/dev/null
_ready_label_mentions="$(grep -c -- 'ready-for-human-review' "$_call_log_12" 2>/dev/null)" || _ready_label_mentions="0"
run_test "reviewer_failed_does_not_touch_ready_label" "0" "$_ready_label_mentions"
rm -f "$_call_log_12"
unset MOCK_GH_CALL_LOG

_reviewer_failed_fn_line="$(grep -n 'reviewer_failed_label_required_for_result()' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
_sync_fn_line="$(grep -n 'sync_reviewer_failed_label()' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
_harness_return_line="$(grep -n '_HARNESS_MODE_EFFECTIVE.*return 0' \
  "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 2>/dev/null \
  | head -1 | cut -d: -f1)"
if [ -n "$_reviewer_failed_fn_line" ] && [ -n "$_sync_fn_line" ] \
    && [ -n "$_harness_return_line" ] \
    && [ "$_reviewer_failed_fn_line" -lt "$_harness_return_line" ] \
    && [ "$_sync_fn_line" -lt "$_harness_return_line" ]; then
  _reviewer_failed_ordering_ok="yes"
else
  _reviewer_failed_ordering_ok="no"
fi
run_test "reviewer_failed_helpers_before_harness_return" "yes" "$_reviewer_failed_ordering_ok"
unset _reviewer_failed_required _reviewer_failed_fn_line _sync_fn_line _harness_return_line _reviewer_failed_ordering_ok
unset MOCK_GH_EXIT MOCK_GH_LABEL_VIEW_EXIT MOCK_GH_LABEL_CREATE_EXIT MOCK_GH_PR_EDIT_EXIT

# ---------------------------------------------------------------------------
# Area 12b: ready-phase gate distinguishes GitHub API rate-limit exhaustion
# from a genuine review-gate failure (issue #1509)
#
# gh_rate_limit_exhausted_reset() and ensure_pr_ready_for_ready_phase() are
# defined before the HARNESS_MODE return point and are therefore callable
# directly from the test harness.
#
# Uses the strict-mock pattern established for issue #1531 (a PATH-installed
# `gh` script that enumerates every invocation the code under test legitimately
# makes and hard-errors on anything else) rather than the permissive global
# MOCK_GH_* fallback used elsewhere in this file — a renamed or dropped
# `gh api rate_limit` call must fail the test, not silently return an empty
# default that happens to still satisfy the assertion.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 12b: rate-limit-aware ready-phase gate (issue #1509) ==="

_1509_mkmock() {
  # $1 = mock dir, $2 = case body (bash `case "$*" in ... esac` arms)
  if [ "$#" -ne 2 ]; then
    echo "ERROR: _1509_mkmock requires exactly 2 arguments (dir, arms), got $#" >&2
    return 1
  fi
  local dir="$1"
  local arms="$2"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    echo "ERROR: _1509_mkmock: '$dir' is not a valid directory" >&2
    return 1
  fi
  if ! cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\$RL1509_CALL_LOG"
case "\$*" in
$arms
  *)
    printf 'UNEXPECTED gh invocation in 1509 mock: %s\n' "\$*" >&2
    exit 1
    ;;
esac
EOF
  then
    echo "ERROR: _1509_mkmock: failed to write $dir/gh" >&2
    return 1
  fi
  if ! chmod +x "$dir/gh"; then
    echo "ERROR: _1509_mkmock: failed to chmod +x $dir/gh" >&2
    return 1
  fi
}

# --- gh_rate_limit_exhausted_reset: core exhausted -------------------------
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":0,"reset":1700000100},"graphql":{"limit":5000,"remaining":5000,"reset":1700009999}}}\n'"'"'
    exit 0 ;;'
_1509_out="$(PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" gh_rate_limit_exhausted_reset)"
_1509_rc=$?
run_test "rl1509_core_exhausted_prints_reset" "1700000100" "$_1509_out"
run_test "rl1509_core_exhausted_exit_0" "0" "$_1509_rc"
run_test "rl1509_core_exhausted_probed_rate_limit" "yes" \
  "$([ "$(grep -c -- 'api rate_limit' "$_1509_log" 2>/dev/null || true)" -ge 1 ] && echo yes || echo no)"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_out _1509_rc

# --- gh_rate_limit_exhausted_reset: graphql exhausted -----------------------
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":5000,"reset":1700009999},"graphql":{"limit":5000,"remaining":0,"reset":1700000200}}}\n'"'"'
    exit 0 ;;'
_1509_out="$(PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" gh_rate_limit_exhausted_reset)"
run_test "rl1509_graphql_exhausted_prints_reset" "1700000200" "$_1509_out"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_out

# --- gh_rate_limit_exhausted_reset: both exhausted -> earliest reset wins --
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":0,"reset":1700000500},"graphql":{"limit":5000,"remaining":0,"reset":1700000300}}}\n'"'"'
    exit 0 ;;'
_1509_out="$(PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" gh_rate_limit_exhausted_reset)"
run_test "rl1509_both_exhausted_earliest_reset" "1700000300" "$_1509_out"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_out

# --- gh_rate_limit_exhausted_reset: neither exhausted -> empty, exit 1 -----
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":4999,"reset":1700009999},"graphql":{"limit":5000,"remaining":5000,"reset":1700009999}}}\n'"'"'
    exit 0 ;;'
set +e
_1509_out="$(PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" gh_rate_limit_exhausted_reset)"
_1509_rc=$?
set -e
run_test "rl1509_not_exhausted_empty_output" "" "$_1509_out"
run_test "rl1509_not_exhausted_exit_1" "1" "$_1509_rc"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_out _1509_rc

# --- gh_rate_limit_exhausted_reset: probe call itself fails -> exit 1 ------
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "api rate_limit")
    exit 1 ;;'
set +e
_1509_out="$(PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" gh_rate_limit_exhausted_reset)"
_1509_rc=$?
set -e
run_test "rl1509_probe_failure_empty_output" "" "$_1509_out"
run_test "rl1509_probe_failure_exit_1" "1" "$_1509_rc"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_out _1509_rc

# --- gh_rate_limit_exhausted_reset: malformed JSON does not abort the caller
# under `set -e` (regression guard for the unguarded-assignment failure mode) --
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "api rate_limit")
    printf '"'"'not-json\n'"'"'
    exit 0 ;;'
set +e
_1509_out="$(PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" gh_rate_limit_exhausted_reset)"
_1509_rc=$?
set -e
run_test "rl1509_malformed_json_empty_output" "" "$_1509_out"
run_test "rl1509_malformed_json_exit_1" "1" "$_1509_rc"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_out _1509_rc

# --- ensure_pr_ready_for_ready_phase: gh pr view failure + confirmed rate
# limit exhaustion -> exit 3, distinct from the generic exit 2, and
# READY_PHASE_GATE_RATE_LIMIT_RESET carries the reset timestamp -------------
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "pr view 999 --json isDraft --jq .isDraft")
    exit 1 ;;
  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":0,"reset":1700000777},"graphql":{"limit":5000,"remaining":5000,"reset":1700009999}}}\n'"'"'
    exit 0 ;;'
set +e
PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" \
  ensure_pr_ready_for_ready_phase "999" >/dev/null 2>&1
_1509_rc=$?
set -e
run_test "rl1509_gate_draft_state_rate_limited_exit_3" "3" "$_1509_rc"
run_test "rl1509_gate_draft_state_rate_limited_reset_captured" "1700000777" \
  "$READY_PHASE_GATE_RATE_LIMIT_RESET"
run_test "rl1509_gate_draft_state_rate_limited_probed" "yes" \
  "$([ "$(grep -c -- 'api rate_limit' "$_1509_log" 2>/dev/null || true)" -ge 1 ] && echo yes || echo no)"
run_test "rl1509_gate_draft_state_rate_limited_did_not_call_pr_ready" "0" \
  "$(grep -c -- 'pr ready 999' "$_1509_log" 2>/dev/null || true)"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_rc

# --- ensure_pr_ready_for_ready_phase: gh pr view failure WITHOUT confirmed
# rate-limit exhaustion still returns the original exit 2 (unchanged
# behavior — an unexplained failure is not asserted to be a rate limit) -----
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "pr view 999 --json isDraft --jq .isDraft")
    exit 1 ;;
  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":4999,"reset":1700009999},"graphql":{"limit":5000,"remaining":5000,"reset":1700009999}}}\n'"'"'
    exit 0 ;;'
READY_PHASE_GATE_RATE_LIMIT_RESET="stale-from-prior-cycle"
set +e
PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" \
  ensure_pr_ready_for_ready_phase "999" >/dev/null 2>&1
_1509_rc=$?
set -e
run_test "rl1509_gate_draft_state_unexplained_failure_exit_2" "2" "$_1509_rc"
run_test "rl1509_gate_unexplained_failure_clears_stale_reset" "" \
  "$READY_PHASE_GATE_RATE_LIMIT_RESET"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_rc

# --- ensure_pr_ready_for_ready_phase: `gh pr ready` failure (after a
# successful draft-state read) + confirmed rate-limit exhaustion -> exit 3 --
_1509_dir="$(mktemp -d)"
_1509_log="$_1509_dir/calls.log"
_1509_mkmock "$_1509_dir" '  "pr view 999 --json isDraft --jq .isDraft")
    printf '"'"'true\n'"'"'
    exit 0 ;;
  "pr ready 999")
    exit 1 ;;
  "api rate_limit")
    printf '"'"'{"resources":{"core":{"limit":5000,"remaining":0,"reset":1700000888},"graphql":{"limit":5000,"remaining":5000,"reset":1700009999}}}\n'"'"'
    exit 0 ;;'
set +e
PATH="$_1509_dir:$PATH" RL1509_CALL_LOG="$_1509_log" \
  ensure_pr_ready_for_ready_phase "999" >/dev/null 2>&1
_1509_rc=$?
set -e
run_test "rl1509_gate_pr_ready_rate_limited_exit_3" "3" "$_1509_rc"
run_test "rl1509_gate_pr_ready_rate_limited_reset_captured" "1700000888" \
  "$READY_PHASE_GATE_RATE_LIMIT_RESET"
rm -rf "$_1509_dir"
unset _1509_dir _1509_log _1509_rc
unset -f _1509_mkmock
READY_PHASE_GATE_RATE_LIMIT_RESET=""

# --- reviewer_failed_label_required_for_result: rate_limited escalation is
# infrastructure unavailability, not a review verdict — no label -----------
#
# Defined locally (not reusing Area 12's _reviewer_failed_required) because
# Area 12 ends by `unset`-ing that name — with neither -f nor -v given, bash
# falls back to unsetting the FUNCTION when no variable by that name exists,
# so the Area 12 helper is gone by the time this block runs.
_1509_reviewer_failed_required() {
  if reviewer_failed_label_required_for_result "$1" "${2:-}"; then
    printf 'yes'
  else
    printf 'no'
  fi
}
run_test "reviewer_failed_escalate_rate_limited_no_label" "no" \
  "$(_1509_reviewer_failed_required escalate rate_limited)"
# Sibling REASON tokens must be unaffected by the new exception (regression
# guard against an over-broad case match swallowing other escalate reasons).
run_test "reviewer_failed_escalate_ready_for_review_failed_still_label" "yes" \
  "$(_1509_reviewer_failed_required escalate ready_for_review_failed)"
unset -f _1509_reviewer_failed_required

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
