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

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
