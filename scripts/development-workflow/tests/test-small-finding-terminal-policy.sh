#!/usr/bin/env bash
# test-small-finding-terminal-policy.sh — #1661 regression replays for #1652.
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md
#
# Scenarios 12, 12a, and 13 from the implementation plan.
# shellcheck shell=bash disable=SC2034

set -euo pipefail

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

export MOCK_REPO_ROOT="$REPO_ROOT"
# shellcheck source=scripts/development-workflow/pr-review-loop.sh
HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

_head="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
_other="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

_finding() {
  jq -cn --arg path "$1" --arg platform "$2" --arg body "$3" \
    '{path: $path, platform: $platform, body: $body}'
}

_ledger_body() {
  local payload="$1"
  printf '%s\n' "### Automated Reviewer Loop Summary

<!-- reviewer-loop-history:v1 -->
\`\`\`json
$(printf '%s\n' "$payload" | jq '.')
\`\`\`"
}

_entry() {
  local iter="$1" path="$2" body="$3"
  jq -n --argjson iter "$iter" --arg h "$_head" --arg path "$path" --arg body "$body" '{
    iteration: $iter,
    result: "needs_fixes",
    small_findings_only: true,
    classification_head: $h,
    contributing_platforms: ["local-ai-reviewer"],
    reviewed_heads: [{platform: "local-ai-reviewer", reviewed_head: $h, state: "current", reason: ""}],
    small_findings_paths: [$path],
    blocking_count: 1
  }'
}

echo "=== test-small-finding-terminal-policy (#1652 scenarios 12/12a/13) ==="

# --- Scenario 12: #1661 regression — tier 1 (normative paths) ---
# Consecutive rounds whose only findings are on docs/specs/developments/**
# must NOT be small, so the terminal rule cannot fire.
_s12_f1="$(_finding "docs/specs/developments/x/1_x_specs.md" "local-ai-reviewer" "fail-closed semantics broken on deny-list")"
_s12_f2="$(_finding "docs/specs/developments/x/1_x_specs.md" "local-ai-reviewer" "decision matrix row is wrong")"
_s12_f3="$(_finding "docs/specs/developments/x/1_x_specs.md" "local-ai-reviewer" "acceptance criteria AC-10 unmet")"
run_test "1652_s12_normative_not_small_fail_closed" "no" \
  "$(printf '%s\n' "$_s12_f1" | reviewer_loop_all_findings_are_small && echo yes || echo no)"
run_test "1652_s12_normative_not_small_matrix" "no" \
  "$(printf '%s\n' "$_s12_f2" | reviewer_loop_all_findings_are_small && echo yes || echo no)"
run_test "1652_s12_normative_not_small_ac" "no" \
  "$(printf '%s\n' "$_s12_f3" | reviewer_loop_all_findings_are_small && echo yes || echo no)"
# Even with cosmetic body on normative path — still not small (tier 1).
_s12_cosmetic="$(_finding "docs/specs/developments/x/1_x_specs.md" "local-ai-reviewer" "trailing whitespace")"
run_test "1652_s12_normative_cosmetic_still_not_small" "no" \
  "$(printf '%s\n' "$_s12_cosmetic" | reviewer_loop_all_findings_are_small && echo yes || echo no)"
# Content analysis reports shipped_path (normative excluded from non-shipped).
run_test "1652_s12_blocked_by_shipped_path" "shipped_path" \
  "$(printf '%s\n' "$_s12_f1" | reviewer_loop_small_findings_content_analysis | jq -r '.blocked_by')"

# --- Scenario 12a: tier-2 isolation on CHANGELOG.md with #1661 bodies ---
_s12a_f1="$(_finding "CHANGELOG.md" "local-ai-reviewer" "fail-closed semantics broken on deny-list")"
_s12a_f2="$(_finding "CHANGELOG.md" "local-ai-reviewer" "decision matrix row is wrong")"
_s12a_f3="$(_finding "CHANGELOG.md" "local-ai-reviewer" "acceptance criteria AC-10 unmet")"
run_test "1652_s12a_changelog_contract_not_small" "no" \
  "$(printf '%s\n' "$_s12a_f1" "$_s12a_f2" "$_s12a_f3" | reviewer_loop_all_findings_are_small && echo yes || echo no)"
run_test "1652_s12a_blocked_by_contract_surface" "contract_surface" \
  "$(printf '%s\n' "$_s12a_f1" | reviewer_loop_small_findings_content_analysis | jq -r '.blocked_by')"
# Simulate two prior "would-be-small" ledger rounds + current contract findings:
# content analysis keeps the round non-small, so terminal cannot fire.
_s12a_payload="$(jq -n --arg h "$_head" '{
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
_s12a_all_small="$(printf '%s\n' "$_s12a_f1" "$_s12a_f2" | reviewer_loop_all_findings_are_small && echo 1 || echo 0)"
run_test "1652_s12a_terminal_cannot_fire" "0" "$_s12a_all_small"

# --- Scenario 13: cosmetic counter-case on same CHANGELOG.md path ---
_s13_f1="$(_finding "CHANGELOG.md" "local-ai-reviewer" "trailing whitespace on bullet")"
_s13_f2="$(_finding "CHANGELOG.md" "local-ai-reviewer" "typo in heading")"
_s13_f3="$(_finding "CHANGELOG.md" "local-ai-reviewer" "heading capitalisation")"
run_test "1652_s13_cosmetic_changelog_is_small" "yes" \
  "$(printf '%s\n' "$_s13_f1" "$_s13_f2" "$_s13_f3" | reviewer_loop_all_findings_are_small && echo yes || echo no)"
# With one prior small round on current head, rounds = 2 → terminal may fire.
_s13_count="$(reviewer_loop_parse_small_findings_count "$(
  reviewer_loop_small_findings_prior_consecutive_count "$(_ledger_body "$_s12a_payload")" "$_head"
)")"
run_test "1652_s13_prior_count_ready" "2 exhausted" "$_s13_count"
# Current-round heads OK for the cosmetic contributor.
_s13_heads="$(printf '%s\n' "local-ai-reviewer" | reviewer_loop_current_round_heads_ok "$_head" "local-ai-reviewer:$_head")"
run_test "1652_s13_current_heads_ok" "ok" "$(printf '%s' "$_s13_heads" | jq -r '.status')"
# Pairing with 12a: same path/head/shape, only bodies differ → opposite outcome.
run_test "1652_s13_opposite_of_12a" "yes" \
  "$(
    a="$(printf '%s\n' "$_s12a_f1" | reviewer_loop_all_findings_are_small && echo small || echo not)"
    b="$(printf '%s\n' "$_s13_f1" | reviewer_loop_all_findings_are_small && echo small || echo not)"
    if [ "$a" = "not" ] && [ "$b" = "small" ]; then echo yes; else echo "a=$a b=$b"; fi
  )"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
