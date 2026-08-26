#!/usr/bin/env bash
# test-workflow-batch-overlap.sh - Unit tests for planless batch overlap detection.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
OVERLAP="$REPO_ROOT/scripts/development-workflow/workflow-batch-overlap.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

write_items() {
  local path="$1"
  shift
  printf '%s\n' "$@" | jq -s '{items: .}' > "$path"
}

item_json() {
  local id="$1" title="$2" brief="$3" file_set="${4:-unknown}" priority="${5:-Normal}" created_at="${6:-2026-01-01T00:00:00Z}" next_action="${7:-implement}" branch="${8:-}"
  jq -cn \
    --arg id "$id" \
    --arg title "$title" \
    --arg brief "$brief" \
    --arg fileSet "$file_set" \
    --arg priority "$priority" \
    --arg createdAt "$created_at" \
    --arg nextAction "$next_action" \
    --arg branch "$branch" \
    '{id:$id,title:$title,brief:$brief,fileSet:$fileSet,priority:$priority,createdAt:$createdAt,nextAction:$nextAction,branch:$branch}'
}

class_for() {
  "$OVERLAP" --input "$1" --json | jq -r '.pairs[0].classification'
}

source_for() {
  "$OVERLAP" --input "$1" --json | jq -r '.pairs[0].source'
}

dispatch_for() {
  if [ -n "${2:-}" ]; then
    "$OVERLAP" --input "$1" --decision-file "$2" --json | jq -r '.pairs[0].defaultDispatch'
  else
    "$OVERLAP" --input "$1" --json | jq -r '.pairs[0].defaultDispatch'
  fi
}

pair_value() {
  "$OVERLAP" --input "$1" --json | jq -r "$2"
}

same_route="$TMP_ROOT/same-route.json"
write_items "$same_route" \
  "$(item_json route-a "Users endpoint" "Update GET /api/users/:id validation.")" \
  "$(item_json route-b "Users logging" "Add tracing for GET /api/users/:id.")"
run_test "same_route_is_concrete" "concrete" "$(class_for "$same_route")"
run_test "same_route_source" "brief" "$(source_for "$same_route")"

parent_route="$TMP_ROOT/parent-route.json"
write_items "$parent_route" \
  "$(item_json parent-a "Users endpoint" "Update GET /api/users.")" \
  "$(item_json parent-b "User details" "Update GET /api/users/:id.")"
run_test "parent_route_is_suspected" "suspected" "$(class_for "$parent_route")"
run_test "suspected_defaults_serial" "serial" "$(dispatch_for "$parent_route")"

same_function="$TMP_ROOT/same-function.json"
write_items "$same_function" \
  "$(item_json fn-a "Policy parser" "Update resolvePolicy() for empty policy.")" \
  "$(item_json fn-b "Policy reporter" "Add tests for function resolvePolicy.")"
run_test "same_function_is_concrete" "concrete" "$(class_for "$same_function")"

same_module="$TMP_ROOT/same-module.json"
write_items "$same_module" \
  "$(item_json mod-a "Review helper" "Change helper \`checkpoint-resume-gate.sh\`.")" \
  "$(item_json mod-b "Review helper docs" "Update script \`checkpoint-resume-gate.sh\`.")"
run_test "same_module_is_concrete" "concrete" "$(class_for "$same_module")"

plan_overlap="$TMP_ROOT/plan-overlap.json"
write_items "$plan_overlap" \
  "$(item_json plan-a "A" "Unrelated text." "src/a.ts,scripts/tool.sh")" \
  "$(item_json plan-b "B" "Another unrelated brief." "scripts/tool.sh,src/b.ts")"
run_test "plan_overlap_remains_concrete" "concrete" "$(class_for "$plan_overlap")"
run_test "plan_overlap_source" "plan" "$(source_for "$plan_overlap")"

fallback_downgrade="$TMP_ROOT/fallback-downgrade.json"
write_items "$fallback_downgrade" \
  "$(item_json plan-c "A" "Update GET /one." "src/shared.ts")" \
  "$(item_json plan-d "B" "Update GET /two." "src/shared.ts")"
run_test "fallback_cannot_downgrade_plan" "plan" "$(source_for "$fallback_downgrade")"

mixed_disagreement="$TMP_ROOT/mixed-disagreement.json"
write_items "$mixed_disagreement" \
  "$(item_json mix-a "A" "Update GET /api/users." "src/a.ts")" \
  "$(item_json mix-b "B" "Update GET /api/users/:id." "src/b.ts")"
run_test "mixed_evidence_disagreement_is_suspected" "suspected" "$(class_for "$mixed_disagreement")"
run_test "mixed_evidence_source" "mixed" "$(source_for "$mixed_disagreement")"

unrelated="$TMP_ROOT/unrelated.json"
write_items "$unrelated" \
  "$(item_json unrelated-a "Billing" "Update GET /api/invoices.")" \
  "$(item_json unrelated-b "Users" "Update reconcileUsers().")"
run_test "unrelated_targets_remain_eligible" "no_actionable_overlap" "$(class_for "$unrelated")"
run_test "unrelated_dispatch" "parallel_eligible" "$(dispatch_for "$unrelated")"

generic="$TMP_ROOT/generic.json"
write_items "$generic" \
  "$(item_json generic-a "Workflow review" "Improve workflow review batch behavior.")" \
  "$(item_json generic-b "Workflow plan" "Improve workflow plan implementation behavior.")"
run_test "generic_terms_do_not_overlap" "no_actionable_overlap" "$(class_for "$generic")"

empty_brief="$TMP_ROOT/empty-brief.json"
write_items "$empty_brief" \
  "$(item_json empty-a "" "")" \
  "$(item_json empty-b "" "")"
run_test "empty_brief_is_no_actionable_overlap" "no_actionable_overlap" "$(class_for "$empty_brief")"

transitive="$TMP_ROOT/transitive.json"
write_items "$transitive" \
  "$(item_json trans-a "A" "Update GET /a." "unknown" "High" "2026-01-01T00:00:00Z")" \
  "$(item_json trans-b "B" "Update GET /a and GET /b." "unknown" "Normal" "2026-01-02T00:00:00Z")" \
  "$(item_json trans-c "C" "Update GET /b." "unknown" "Normal" "2026-01-03T00:00:00Z")"
run_test "transitive_overlaps_form_one_serial_group" "trans-a,trans-b,trans-c" "$(pair_value "$transitive" '.serialGroups[0].itemIds | join(",")')"
run_test "priority_orders_serial_keep" "trans-a" "$(pair_value "$transitive" '.serialGroups[0].keepItemId')"

branch_tie="$TMP_ROOT/branch-tie.json"
write_items "$branch_tie" \
  "$(item_json tie-z "Shared A" "Update GET /tie." "unknown" "Normal" "2026-01-01T00:00:00Z" "implement" "feature/a-branch")" \
  "$(item_json tie-a "Shared B" "Update GET /tie." "unknown" "Normal" "2026-01-01T00:00:00Z" "implement" "feature/z-branch")"
run_test "branch_orders_serial_keep" "tie-z" "$(pair_value "$branch_tie" '.serialGroups[0].keepItemId')"

decision_probe="$("$OVERLAP" --input "$parent_route" --json)"
batch_fp="$(printf '%s\n' "$decision_probe" | jq -r '.batchFingerprint')"
evidence_hash="$(printf '%s\n' "$decision_probe" | jq -r '.pairs[0].evidenceHash')"
decision_file="$TMP_ROOT/decisions.jsonl"
printf '{"batchFingerprint":"%s","pairId":"parent-a--parent-b","evidenceHash":"%s","decision":"allow_parallel","recordedHumanInstruction":"approved current suspected pair"}\n' "$batch_fp" "$evidence_hash" > "$decision_file"
run_test "matching_pair_decision_allows_parallel" "parallel_eligible" "$(dispatch_for "$parent_route" "$decision_file")"

reversed_decision="$TMP_ROOT/reversed-decisions.jsonl"
printf '{"batchFingerprint":"%s","itemIds":["parent-b","parent-a"],"evidenceHash":"%s","decision":"allow_parallel"}\n' "$batch_fp" "$evidence_hash" > "$reversed_decision"
run_test "allow_parallel_requires_human_instruction" "serial" "$(dispatch_for "$parent_route" "$reversed_decision")"

reversed_instruction_decision="$TMP_ROOT/reversed-instruction-decisions.jsonl"
printf '{"batchFingerprint":"%s","itemIds":["parent-b","parent-a"],"evidenceHash":"%s","decision":"allow_parallel","recordedHumanInstruction":"approved current suspected pair in reverse order"}\n' "$batch_fp" "$evidence_hash" > "$reversed_instruction_decision"
run_test "reversed_pair_order_matches_with_instruction" "parallel_eligible" "$(dispatch_for "$parent_route" "$reversed_instruction_decision")"
run_test "missing_instruction_marked_stale" "missing_human_instruction" "$("$OVERLAP" --input "$parent_route" --decision-file "$reversed_decision" --json | jq -r '.staleDecisions[0].status')"

null_instruction_decision="$TMP_ROOT/null-instruction-decisions.jsonl"
printf '{"batchFingerprint":"%s","pairId":"parent-a--parent-b","evidenceHash":"%s","decision":"allow_parallel","recordedHumanInstruction":null}\n' "$batch_fp" "$evidence_hash" > "$null_instruction_decision"
run_test "null_recorded_instruction_rejected" "missing_human_instruction" "$("$OVERLAP" --input "$parent_route" --decision-file "$null_instruction_decision" --json | jq -r '.staleDecisions[0].status')"

false_instruction_decision="$TMP_ROOT/false-instruction-decisions.jsonl"
printf '{"batchFingerprint":"%s","pairId":"parent-a--parent-b","evidenceHash":"%s","decision":"allow_parallel","recordedHumanInstruction":false}\n' "$batch_fp" "$evidence_hash" > "$false_instruction_decision"
run_test "false_recorded_instruction_rejected" "missing_human_instruction" "$("$OVERLAP" --input "$parent_route" --decision-file "$false_instruction_decision" --json | jq -r '.staleDecisions[0].status')"

numeric_instruction_decision="$TMP_ROOT/numeric-instruction-decisions.jsonl"
printf '{"batchFingerprint":"%s","pairId":"parent-a--parent-b","evidenceHash":"%s","decision":"allow_parallel","recordedHumanInstruction":0}\n' "$batch_fp" "$evidence_hash" > "$numeric_instruction_decision"
run_test "numeric_recorded_instruction_rejected" "missing_human_instruction" "$("$OVERLAP" --input "$parent_route" --decision-file "$numeric_instruction_decision" --json | jq -r '.staleDecisions[0].status')"

whitespace_instruction_decision="$TMP_ROOT/whitespace-instruction-decisions.jsonl"
printf '{"batchFingerprint":"%s","pairId":"parent-a--parent-b","evidenceHash":"%s","decision":"allow_parallel","recordedHumanInstruction":"   "}\n' "$batch_fp" "$evidence_hash" > "$whitespace_instruction_decision"
run_test "whitespace_recorded_instruction_rejected" "missing_human_instruction" "$("$OVERLAP" --input "$parent_route" --decision-file "$whitespace_instruction_decision" --json | jq -r '.staleDecisions[0].status')"

stale_decision="$TMP_ROOT/stale-decisions.jsonl"
printf '{"batchFingerprint":"sha256:stale","pairId":"parent-a--parent-b","evidenceHash":"%s","decision":"allow_parallel"}\n' "$evidence_hash" > "$stale_decision"
run_test "stale_decision_does_not_apply" "serial" "$(dispatch_for "$parent_route" "$stale_decision")"

duplicate_ids="$TMP_ROOT/duplicate.json"
write_items "$duplicate_ids" \
  "$(item_json dup "A" "GET /a")" \
  "$(item_json dup "B" "GET /b")"
run_test "duplicate_ids_rejected" "yes" "$("$OVERLAP" --input "$duplicate_ids" --json >/dev/null 2>&1 && echo no || echo yes)"

missing_fields="$TMP_ROOT/missing-fields.json"
jq -n '{items:[{id:"a",title:"A"},{id:"b",title:"B",nextAction:"implement"}]}' > "$missing_fields"
run_test "missing_fields_fail_closed" "yes" "$("$OVERLAP" --input "$missing_fields" --json >/dev/null 2>&1 && echo no || echo yes)"

invalid_json="$TMP_ROOT/invalid.json"
printf '{"items": [' > "$invalid_json"
run_test "invalid_json_rejected" "yes" "$("$OVERLAP" --input "$invalid_json" --json >/dev/null 2>&1 && echo no || echo yes)"

reordered="$TMP_ROOT/reordered.json"
write_items "$reordered" \
  "$(item_json route-b "Users logging" "Add tracing for GET /api/users/:id.")" \
  "$(item_json route-a "Users endpoint" "Update GET /api/users/:id validation.")"
run_test "input_order_is_stable" "$(pair_value "$same_route" '.pairs[0].pairId')" "$(pair_value "$reordered" '.pairs[0].pairId')"

# --- Issue #1540: verb-capture module signals + one-sided-evidence false serialization ---

# AC-1: minimal reproduction from the issue must classify as fully independent.
minimal_repro="$TMP_ROOT/minimal-repro-1540.json"
write_items "$minimal_repro" \
  "$(item_json A "Alpha" "the helper emits false rows" "scripts/alpha.sh")" \
  "$(item_json B "Beta" "completely unrelated change" "scripts/beta.sh")"
run_test "minimal_repro_is_no_actionable_overlap" "no_actionable_overlap" "$(class_for "$minimal_repro")"
run_test "minimal_repro_dispatch_is_parallel" "parallel_eligible" "$(dispatch_for "$minimal_repro")"
run_test "minimal_repro_drops_bogus_module_signal" "0" "$(pair_value "$minimal_repro" '[.pairs[0].signals.leftSignals[] | select(.type=="module")] | length')"

# AC-2: an English verb following a module cue must not become a "module" signal,
# for each of the three fixtures named in the issue's acceptance criteria.
verb_emits="$TMP_ROOT/verb-emits.json"
write_items "$verb_emits" \
  "$(item_json ve-a "A" "the helper emits false discrepancy rows" "scripts/x/emits-a.sh")" \
  "$(item_json ve-b "B" "an unrelated brief with no cues" "scripts/x/emits-b.sh")"
run_test "verb_emits_not_captured" "no_actionable_overlap" "$(class_for "$verb_emits")"
run_test "verb_emits_drops_bogus_module_signal" "0" "$(pair_value "$verb_emits" '[.pairs[0].signals.leftSignals[] | select(.type=="module")] | length')"

verb_hardcodes="$TMP_ROOT/verb-hardcodes.json"
write_items "$verb_hardcodes" \
  "$(item_json vh-a "A" "the script hardcodes a type field path" "scripts/x/hardcodes-a.sh")" \
  "$(item_json vh-b "B" "an unrelated brief with no cues" "scripts/x/hardcodes-b.sh")"
run_test "verb_hardcodes_not_captured" "no_actionable_overlap" "$(class_for "$verb_hardcodes")"
run_test "verb_hardcodes_drops_bogus_module_signal" "0" "$(pair_value "$verb_hardcodes" '[.pairs[0].signals.leftSignals[] | select(.type=="module")] | length')"

verb_returns="$TMP_ROOT/verb-returns.json"
write_items "$verb_returns" \
  "$(item_json vr-a "A" "the component returns unrelated data" "scripts/x/returns-a.sh")" \
  "$(item_json vr-b "B" "an unrelated brief with no cues" "scripts/x/returns-b.sh")"
run_test "verb_returns_not_captured" "no_actionable_overlap" "$(class_for "$verb_returns")"
run_test "verb_returns_drops_bogus_module_signal" "0" "$(pair_value "$verb_returns" '[.pairs[0].signals.leftSignals[] | select(.type=="module")] | length')"

# AC-3 control: genuinely overlapping pairs must still classify concrete, including
# via an unquoted-but-identifier-shaped module name (proves the validator does not
# reject real module names, only bare English words).
overlapping_module="$TMP_ROOT/overlapping-module.json"
write_items "$overlapping_module" \
  "$(item_json om-a "A" "Change helper token-resolver for consistency.")" \
  "$(item_json om-b "B" "Update script token-resolver to match.")"
run_test "overlapping_unquoted_module_stays_concrete" "concrete" "$(class_for "$overlapping_module")"
run_test "overlapping_unquoted_module_source" "brief" "$(source_for "$overlapping_module")"

# AC-4: the wave-1 and wave-2 sets from the issue's observed-impact section must
# be fully parallel-eligible (no serial groups) after the fix.
wave1="$TMP_ROOT/wave1.json"
write_items "$wave1" \
  "$(item_json i1503 "Fix token resolution bug" "resolve_token() returns a stale token under load." "scripts/development-workflow/resolve-token.sh")" \
  "$(item_json i1504 "Improve report formatting" "Report rows misalign in the summary table." "scripts/development-workflow/report-format.sh")" \
  "$(item_json i1511 "Add edge case fixture" "Add coverage for an edge case scenario." "scripts/development-workflow/tests/test-edge-case.sh")" \
  "$(item_json i1516 "Tidy up dead code" "Remove an unused variable in the reporting flow." "scripts/development-workflow/cleanup.sh")"
run_test "wave1_has_no_serial_groups" "0" "$(pair_value "$wave1" '.serialGroups | length')"
run_test "wave1_all_pairs_parallel_eligible" "6" "$(pair_value "$wave1" '[.pairs[] | select(.defaultDispatch=="parallel_eligible")] | length')"

wave2="$TMP_ROOT/wave2.json"
write_items "$wave2" \
  "$(item_json i1333 "Alpha work" "the helper emits false rows in the report." "scripts/x/alpha.sh")" \
  "$(item_json i1400 "Beta work" "the script hardcodes a path that should be configurable." "scripts/x/beta.sh")" \
  "$(item_json i1503b "Gamma work" "Improve token handling reliability." "scripts/x/gamma.sh")" \
  "$(item_json i1509 "Delta work" "Add coverage for token edge cases." "scripts/x/delta.sh")"
run_test "wave2_has_no_serial_groups" "0" "$(pair_value "$wave2" '.serialGroups | length')"
run_test "wave2_all_pairs_parallel_eligible" "6" "$(pair_value "$wave2" '[.pairs[] | select(.defaultDispatch=="parallel_eligible")] | length')"

# AC-5: "suspected" explanations must name the specific triggering signal, not a
# generic identical string for every pair.
related_explanation="$(pair_value "$parent_route" '.pairs[0].explanation')"
run_test "related_explanation_names_routes" "yes" "$(printf '%s' "$related_explanation" | grep -q "/api/users" && echo yes || echo no)"

two_sided_mismatch="$TMP_ROOT/two-sided-mismatch.json"
write_items "$two_sided_mismatch" \
  "$(item_json tsm-a "A" "resolveAlpha() has a bug." "a.ts")" \
  "$(item_json tsm-b "B" "resolveBeta() has a bug." "b.ts")"
run_test "two_sided_mismatch_is_suspected" "suspected" "$(class_for "$two_sided_mismatch")"
mismatch_explanation="$(pair_value "$two_sided_mismatch" '.pairs[0].explanation')"
run_test "mismatch_explanation_names_signals" "yes" "$(printf '%s' "$mismatch_explanation" | grep -q "resolvealpha" && printf '%s' "$mismatch_explanation" | grep -q "resolvebeta" && echo yes || echo no)"

# Defect 2 regression: one side having signals while the other has none (with
# shared_files already ruled out) must fall through to no_actionable_overlap
# instead of defaulting to suspected/serial.
one_sided="$TMP_ROOT/one-sided.json"
write_items "$one_sided" \
  "$(item_json os-a "A" "resolveGamma() has a bug." "gamma.ts")" \
  "$(item_json os-b "B" "an unrelated brief with no signals." "delta.ts")"
run_test "one_sided_evidence_is_no_actionable_overlap" "no_actionable_overlap" "$(class_for "$one_sided")"
run_test "one_sided_evidence_dispatch_is_parallel" "parallel_eligible" "$(dispatch_for "$one_sided")"

# Defect 1 residual: an English verb immediately followed by terminal
# punctuation (no words after it) must not become a module signal either.
# The unquoted-cue capture group includes "." in its character class, so a
# trailing sentence period was previously mistaken for a dot-extension.
verb_terminal_period="$TMP_ROOT/verb-terminal-period.json"
write_items "$verb_terminal_period" \
  "$(item_json vtp-a "A" "the script fails." "scripts/x/period-a.sh")" \
  "$(item_json vtp-b "B" "resolveBeta() has a bug." "scripts/x/period-b.sh")"
run_test "verb_terminal_period_not_captured" "no_actionable_overlap" "$(class_for "$verb_terminal_period")"
run_test "verb_terminal_period_drops_bogus_module_signal" "0" "$(pair_value "$verb_terminal_period" '[.pairs[0].signals.leftSignals[] | select(.type=="module")] | length')"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
