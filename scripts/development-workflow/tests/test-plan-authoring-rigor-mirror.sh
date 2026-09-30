#!/usr/bin/env bash
# test-plan-authoring-rigor-mirror.sh - Mirror-consistency coverage for the
# plan-authoring rigor rules (issue #1496): confirms every mirror surface
# agrees with the canonical file on rule names, outcome labels, and the
# canonical path, and that the harness's own parser logic handles the
# documented edge cases (heading boundaries, negative lookalikes, multiple
# mentions on one line, nested link references, and outcome-label casing).
#
# This is a doc-consistency check. It does not detect or enforce the six
# plan-authoring rules against plan text (spec Out of Scope); it only
# detects drift between the canonical file and its mirrors.
#
# covers: docs/workflow/development-workflow/plan-authoring-rigor-rules.md
# covers: docs/workflow/development-workflow/protocols/02-review-implementation-plan-protocol.md
# covers: docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md
# covers: REVIEW.md
# covers: docs/workflow/development-workflow/templates/implementation-plan-template.md
# covers: .claude/agents/tech-lead.md
# covers: .cursor/agents/tech-lead.md
# covers: .claude/agents/implementation-plan-reviewer.md
# covers: .cursor/agents/implementation-plan-reviewer.md
# covers: .codex/skills/workflow-plan-writer/SKILL.md

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

# Fixture-root injection: every path below resolves under $ROOT, never an
# absolute or cwd-relative repo path directly. The default run uses the live
# repository; a planted-violation run points PLAN_RIGOR_ROOT at a mutated
# temp tree that mirrors the repo layout.
ROOT="${PLAN_RIGOR_ROOT:-$REPO_ROOT}"

CANON="$ROOT/docs/workflow/development-workflow/plan-authoring-rigor-rules.md"
REVIEWMD="$ROOT/REVIEW.md"
PROTO02="$ROOT/docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md"
PROTO02REVIEW="$ROOT/docs/workflow/development-workflow/protocols/02-review-implementation-plan-protocol.md"
TEMPLATE="$ROOT/docs/workflow/development-workflow/templates/implementation-plan-template.md"
TECHLEAD_CLAUDE="$ROOT/.claude/agents/tech-lead.md"
TECHLEAD_CURSOR="$ROOT/.cursor/agents/tech-lead.md"
REVIEWER_CLAUDE="$ROOT/.claude/agents/implementation-plan-reviewer.md"
REVIEWER_CURSOR="$ROOT/.cursor/agents/implementation-plan-reviewer.md"
PLANWRITER_SKILL="$ROOT/.codex/skills/workflow-plan-writer/SKILL.md"
FIXDIR="$ROOT/scripts/development-workflow/tests/fixtures/plan-authoring-rigor"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [ "$expected" = "$actual" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

file_exists() {
  if [ -f "$1" ]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

contains() {
  local needle="$1"
  local file="$2"

  if [ -f "$file" ] && grep -Fq -- "$needle" "$file"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

# heading_count counts real markdown headings of the form "### Rule N" at the
# start of a line, skipping fenced code blocks and lines that are HTML
# comments, and never matching a longer number that merely starts with N
# (e.g. counting "Rule 1" never matches a "### Rule 10" heading).
heading_count() {
  local file="$1"
  local n="$2"

  if [ ! -f "$file" ]; then
    printf '0\n'
    return
  fi

  awk -v n="$n" '
    /^```/ { infence = !infence; next }
    infence { next }
    /^<!--/ { next }
    $0 ~ "^### Rule " n "([ —]|$)" { count++ }
    END { print count + 0 }
  ' "$file"
}

# --- Canonical file presence (fail immediately with a message naming the
# missing path if absent; downstream heading/label checks report their own
# expected-vs-actual mismatch against the same missing file). ---
run_test "canonical_file_present" "yes" "$(file_exists "$CANON")"

# --- Canonical file: Rule 1-6 headings present ---
for n in 1 2 3 4 5 6; do
  run_test "canonical_rule_${n}_heading_present" "1" "$(heading_count "$CANON" "$n")"
done

# --- Canonical file: all three outcome labels present, case-sensitively ---
run_test "canonical_outcome_label_satisfied" "yes" "$(contains "Satisfied" "$CANON")"
run_test "canonical_outcome_label_not_applicable" "yes" "$(contains "Not applicable" "$CANON")"
run_test "canonical_outcome_label_unsatisfied" "yes" "$(contains "Unsatisfied" "$CANON")"

# --- REVIEW.md: canonical-path reference ---
run_test "review_canonical_path_reference" "yes" "$(contains "plan-authoring-rigor-rules.md" "$REVIEWMD")"

# --- REVIEW.md: all six rule names present ---
review_all_rule_names_present() {
  local all="yes"
  local names=(
    "Rule 1 — Sampling an external output distribution"
    "Rule 2 — One normative statement per fact"
    "Rule 3 — Counts of codebase artifacts"
    "Rule 4 — Independent verification of existence claims"
    "Rule 5 — Expectations at the composed call site"
    "Rule 6 — A conditional obligation names its scope"
  )
  local name
  for name in "${names[@]}"; do
    if [ "$(contains "$name" "$REVIEWMD")" = "no" ]; then
      all="no"
    fi
  done
  printf '%s\n' "$all"
}
run_test "review_all_six_rule_names_present" "yes" "$(review_all_rule_names_present)"

# --- REVIEW.md: all three outcome labels present ---
run_test "review_outcome_label_satisfied" "yes" "$(contains "Satisfied" "$REVIEWMD")"
run_test "review_outcome_label_not_applicable" "yes" "$(contains "Not applicable" "$REVIEWMD")"
run_test "review_outcome_label_unsatisfied" "yes" "$(contains "Unsatisfied" "$REVIEWMD")"

# --- Protocol 02: canonical-path reference, outcome-record heading, labels ---
run_test "protocol02_canonical_path_reference" "yes" "$(contains "plan-authoring-rigor-rules.md" "$PROTO02")"
run_test "protocol02_outcome_record_heading" "yes" "$(contains "Plan authoring rigor — per-rule outcome record" "$PROTO02")"
run_test "protocol02_outcome_label_satisfied" "yes" "$(contains "Satisfied" "$PROTO02")"
run_test "protocol02_outcome_label_not_applicable" "yes" "$(contains "Not applicable" "$PROTO02")"
run_test "protocol02_outcome_label_unsatisfied" "yes" "$(contains "Unsatisfied" "$PROTO02")"

# --- Mirror surfaces: canonical-path reference (tech-lead + reviewer agents
# for Claude and Cursor, Codex plan-writer skill, plan template, Protocol 02
# review wrapper). Three of these six had no prior drift assertion: the
# Codex plan-writer skill, the plan template, and the Protocol 02 review
# wrapper. ---
run_test "tech_lead_claude_canonical_reference" "yes" "$(contains "plan-authoring-rigor-rules.md" "$TECHLEAD_CLAUDE")"
run_test "tech_lead_cursor_canonical_reference" "yes" "$(contains "plan-authoring-rigor-rules.md" "$TECHLEAD_CURSOR")"
run_test "reviewer_claude_canonical_reference" "yes" "$(contains "plan-authoring-rigor-rules.md" "$REVIEWER_CLAUDE")"
run_test "reviewer_cursor_canonical_reference" "yes" "$(contains "plan-authoring-rigor-rules.md" "$REVIEWER_CURSOR")"
run_test "workflow_plan_writer_skill_canonical_reference" "yes" "$(contains "plan-authoring-rigor-rules.md" "$PLANWRITER_SKILL")"
run_test "implementation_plan_template_canonical_reference" "yes" "$(contains "plan-authoring-rigor-rules.md" "$TEMPLATE")"
run_test "protocol02_review_canonical_reference" "yes" "$(contains "plan-authoring-rigor-rules.md" "$PROTO02REVIEW")"

# --- Parser-risk edge cases (test the harness's own parsing logic against
# fixture snippets, not the live mirror files). ---

# Boundary heading: counting "Rule 1" must not also match a "### Rule 10"
# heading, and must not count an inline prose mention.
run_test "parser_edge_boundary_heading_counts_exact_rule_1_only" "1" "$(heading_count "$FIXDIR/boundary-heading.md" 1)"

# Negative lookalike: a heading-shaped line inside a fenced code block or an
# HTML comment must not count as a real heading.
run_test "parser_edge_negative_lookalike_excludes_fence_and_comment" "0" "$(heading_count "$FIXDIR/negative-lookalike.md" 1)"

# Multiple mentions on one line: line-level grep may match both; heading-
# level counting remains authoritative and is not confused by the same line.
run_test "parser_edge_multiple_on_one_line_matches_rule_1" "yes" "$(contains "Rule 1" "$FIXDIR/multiple-on-one-line.md")"
run_test "parser_edge_multiple_on_one_line_matches_rule_2" "yes" "$(contains "Rule 2" "$FIXDIR/multiple-on-one-line.md")"
run_test "parser_edge_multiple_on_one_line_heading_level_not_confused" "0" "$(heading_count "$FIXDIR/multiple-on-one-line.md" 1)"

# Nested context: a markdown link's path target satisfies a path-based
# reference check without requiring a bare "Rule 3" substring elsewhere.
run_test "parser_edge_nested_link_reference_path_match" "yes" "$(contains "plan-authoring-rigor-rules.md" "$FIXDIR/nested-link-reference.md")"

# Outcome label casing: a case-sensitive display-label check must accept the
# correct-case fixture and reject the code-value-cased fixture.
run_test "parser_edge_outcome_label_correct_case_passes" "yes" "$(contains "Satisfied" "$FIXDIR/outcome-labels-correct-case.md")"
run_test "parser_edge_outcome_label_wrong_case_fails" "no" "$(contains "Satisfied" "$FIXDIR/outcome-labels-wrong-case.md")"

echo ""
echo "${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
