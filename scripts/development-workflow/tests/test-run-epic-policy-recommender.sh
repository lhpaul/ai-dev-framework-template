#!/usr/bin/env bash
# test-run-epic-policy-recommender.sh - Unit tests for /run-epic policy recommendation.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
HELPER="$REPO_ROOT/scripts/development-workflow/run-epic-policy-recommender.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/calls.log"
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$MOCK_CALL_LOG"
case "$*" in
  issue\ edit*|pr\ create*|pr\ edit*|pr\ merge*|pr\ comment*|project\ item-edit*|project\ item-add*|api*)
    printf 'mutating or network gh command was called: gh %s\n' "$*" >&2
    exit 99
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH

cat > "$MOCK_BIN/git" <<'MOCK_GIT'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$MOCK_CALL_LOG"
case "$*" in
  checkout*|switch*|reset*|restore*|push*|commit*|merge*)
    printf 'mutating git command was called: git %s\n' "$*" >&2
    exit 99
    ;;
  *)
    printf 'unexpected git invocation: git %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GIT

chmod +x "$MOCK_BIN/gh" "$MOCK_BIN/git"
export MOCK_CALL_LOG="$CALL_LOG"

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

run_fails_contains() {
  local name="$1" expected="$2"
  shift 2
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ] && grep -Fq -- "$expected" <<< "$output"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected failure containing '${expected}'"
    printf 'Status: %s\nOutput:\n%s\n' "$status" "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

write_fixture() {
  local name="$1" content="$2"
  local path="$TMP_ROOT/${name}.json"
  printf '%s\n' "$content" > "$path"
  printf '%s\n' "$path"
}

recommend_json() {
  "$HELPER" --scope "$1" --original-command "$2" --json
}

echo ""
echo "=== Run epic policy recommender ==="

missing_file="$TMP_ROOT/missing.json"
empty_file="$TMP_ROOT/empty.json"
malformed_file="$TMP_ROOT/malformed.json"
: > "$empty_file"
printf '{"oops"\n' > "$malformed_file"

run_fails_contains "requires_scope" "--scope is required" "$HELPER" --original-command "\$run-epic --items 1"
run_fails_contains "requires_original_command" "--original-command is required" "$HELPER" --scope "$missing_file"
run_fails_contains "rejects_flag_as_scope_value" "--scope requires a value" "$HELPER" --scope --json --original-command x
run_fails_contains "rejects_flag_as_original_command_value" "--original-command requires a value" "$HELPER" --scope "$missing_file" --original-command --json
run_fails_contains "rejects_bad_backlog_bool" "--may-start-backlog must be true or false" "$HELPER" --scope "$missing_file" --original-command x --may-start-backlog maybe
run_fails_contains "rejects_bad_delegate_bool" "--delegate-review must be true or false" "$HELPER" --scope "$missing_file" --original-command x --delegate-review=maybe
run_fails_contains "rejects_bad_merge_bool" "--may-merge must be true or false" "$HELPER" --scope "$missing_file" --original-command x --may-merge=maybe
run_fails_contains "rejects_bad_max_risk" "--max-risk must be one of low, medium, or high" "$HELPER" --scope "$missing_file" --original-command x --max-risk blocked
run_fails_contains "rejects_missing_scope" "scope file not found" "$HELPER" --scope "$missing_file" --original-command x
run_fails_contains "rejects_empty_scope" "scope file is empty" "$HELPER" --scope "$empty_file" --original-command x
run_fails_contains "rejects_malformed_scope" "scope file is not valid JSON" "$HELPER" --scope "$malformed_file" --original-command x

bad_shape_fixture="$(write_fixture bad-shape '{"items":[],"policy":{}}')"
run_fails_contains "rejects_missing_groups" "scope JSON must include" "$HELPER" --scope "$bad_shape_fixture" --original-command x

backlog_fixture="$(write_fixture backlog '{
  "scopeSource": "items",
  "epicNumber": null,
  "itemInput": "949",
  "baseBranch": "develop",
  "baseAmbiguous": false,
  "baseReason": "no integration branch label",
  "policy": {"delegateReview": false, "mayMerge": false, "mayStartBacklog": false, "maxRisk": "low"},
  "groups": {
    "eligible": [{"number": 949, "title": "Improve /run-epic interactive autonomy defaults", "status": "Backlog", "type": "Refactor", "labels": [], "dependencies": {"state": "none"}}],
    "blocked": [],
    "already_merged": [],
    "in_review": [],
    "ambiguous": []
  },
  "items": [
    {"number": 949, "title": "Improve /run-epic interactive autonomy defaults", "status": "Backlog", "type": "Refactor", "labels": [], "dependencies": {"state": "none"}}
  ]
}')"

backlog_output="$(recommend_json "$backlog_fixture" "\$run-epic issues 949")"
run_test "recommends_backlog_start" "true" "$(printf '%s\n' "$backlog_output" | jq -r '.recommendedPolicy.mayStartBacklog')"
run_test "recommends_delegated_review" "true" "$(printf '%s\n' "$backlog_output" | jq -r '.recommendedPolicy.delegateReview')"
run_test "recommends_merge_when_scope_safe" "true" "$(printf '%s\n' "$backlog_output" | jq -r '.recommendedPolicy.mayMerge')"
run_test "workflow_scope_recommends_medium" "medium" "$(printf '%s\n' "$backlog_output" | jq -r '.recommendedPolicy.maxRisk')"
run_test "missing_values_require_confirmation" "true" "$(printf '%s\n' "$backlog_output" | jq -r '.requiresConfirmation')"
run_test "copy_paste_contains_effective_flags" "yes" "$(printf '%s\n' "$backlog_output" | jq -r '.copyPasteCommand' | grep -Fq -- '--may-start-backlog true --max-risk medium --base develop' && echo yes || echo no)"

blocked_fixture="$(write_fixture blocked "$(jq '.groups.blocked = [.groups.eligible[0] | .dependencies.state = "blocked"] | .groups.eligible = [] | .items[0].dependencies.state = "blocked"' "$backlog_fixture")")"
blocked_output="$(recommend_json "$blocked_fixture" "\$run-epic --items 949")"
run_test "blocked_backlog_recommends_no_start" "false" "$(printf '%s\n' "$blocked_output" | jq -r '.recommendedPolicy.mayStartBacklog')"
run_test "blocked_backlog_explains_reason" "yes" "$(printf '%s\n' "$blocked_output" | jq -r '.rationale.mayStartBacklog' | grep -q 'blocked or ambiguous' && echo yes || echo no)"

ambiguous_fixture="$(write_fixture ambiguous "$(jq '.baseBranch = null | .baseAmbiguous = true | .baseReason = "conflicting integration labels"' "$backlog_fixture")")"
ambiguous_output="$(recommend_json "$ambiguous_fixture" "\$run-epic --items 949")"
run_test "ambiguous_base_requires_confirmation" "true" "$(printf '%s\n' "$ambiguous_output" | jq -r '.requiresConfirmation')"
run_test "ambiguous_base_omits_copy_paste_base" "yes" "$(printf '%s\n' "$ambiguous_output" | jq -r '.copyPasteCommand' | grep -Fq -- '--base' && echo no || echo yes)"

explicit_output="$("$HELPER" \
  --scope "$backlog_fixture" \
  --original-command "\$run-epic --items 949" \
  --delegate-review \
  --may-merge \
  --may-start-backlog false \
  --max-risk low \
  --base develop \
  --json)"
run_test "explicit_policy_always_confirms" "true" "$(printf '%s\n' "$explicit_output" | jq -r '.requiresConfirmation')"
run_test "explicit_backlog_choice_preserved" "false" "$(printf '%s\n' "$explicit_output" | jq -r '.effectivePolicy.mayStartBacklog')"
run_test "explicit_sources_recorded" "explicit" "$(printf '%s\n' "$explicit_output" | jq -r '.fieldSources.maxRisk')"
run_test "copy_paste_command_is_canonical" "1" "$(printf '%s\n' "$explicit_output" | jq -r '.copyPasteCommand' | grep -o -- '--max-risk' | wc -l | tr -d ' ')"

disabled_output="$("$HELPER" \
  --scope "$backlog_fixture" \
  --original-command "\$run-epic --items 949 --delegate-review --may-merge" \
  --no-delegate-review \
  --no-may-merge \
  --may-start-backlog false \
  --max-risk low \
  --base develop \
  --json)"
run_test "explicit_delegate_disable_preserved" "false" "$(printf '%s\n' "$disabled_output" | jq -r '.effectivePolicy.delegateReview')"
run_test "explicit_merge_disable_preserved" "false" "$(printf '%s\n' "$disabled_output" | jq -r '.effectivePolicy.mayMerge')"
run_test "disabled_sources_recorded" "explicit" "$(printf '%s\n' "$disabled_output" | jq -r '.fieldSources.delegateReview')"
run_test "disabled_copy_paste_omits_positive_flags" "yes" "$(printf '%s\n' "$disabled_output" | jq -r '.copyPasteCommand' | grep -Eq -- '--delegate-review|--may-merge' && echo no || echo yes)"

assignment_output="$("$HELPER" \
  --scope "$backlog_fixture" \
  --original-command "\$run-epic --items 949" \
  --delegate-review=false \
  --may-merge=false \
  --may-start-backlog false \
  --max-risk low \
  --base develop \
  --json)"
run_test "assignment_false_supported" "false:false" "$(printf '%s\n' "$assignment_output" | jq -r '(.effectivePolicy.delegateReview | tostring) + ":" + (.effectivePolicy.mayMerge | tostring)')"

docs_fixture="$(write_fixture docs '{
  "scopeSource": "items",
  "epicNumber": null,
  "itemInput": "1",
  "baseBranch": "develop",
  "baseAmbiguous": false,
  "baseReason": "no integration branch label",
  "policy": {"delegateReview": false, "mayMerge": false, "mayStartBacklog": false, "maxRisk": "low"},
  "groups": {"eligible": [], "blocked": [], "already_merged": [], "in_review": [{"number": 1, "title": "documentation wording update", "status": "Plan in Review", "type": "Refactor", "labels": []}], "ambiguous": []},
  "items": [{"number": 1, "title": "documentation wording update", "status": "Plan in Review", "type": "Refactor", "labels": []}]
}')"
docs_output="$(recommend_json "$docs_fixture" "\$run-epic --items 1")"
run_test "docs_scope_recommends_low" "low" "$(printf '%s\n' "$docs_output" | jq -r '.recommendedPolicy.maxRisk')"

text_output="$("$HELPER" --scope "$backlog_fixture" --original-command "\$run-epic issues 949")"
run_test "text_output_names_effective_policy" "yes" "$(grep -q 'Effective policy' <<< "$text_output" && grep -q 'Copy-paste equivalent' <<< "$text_output" && echo yes || echo no)"

item_text_output="$("$HELPER" --scope "$backlog_fixture" --original-command "/run-item 949")"
run_test "run_item_text_output_heading" "yes" "$(
  grep -q 'Run Item Policy Recommendation' <<< "$item_text_output" &&
  ! grep -q 'Run Epic Policy Recommendation' <<< "$item_text_output" &&
  echo yes || echo no
)"

items_text_output="$("$HELPER" --scope "$backlog_fixture" --original-command "/run-items 949 950")"
run_test "run_items_text_output_heading" "yes" "$(
  grep -q 'Run Items Policy Recommendation' <<< "$items_text_output" &&
  ! grep -q 'Run Item Policy Recommendation' <<< "$items_text_output" &&
  echo yes || echo no
)"

itemized_text_output="$("$HELPER" --scope "$backlog_fixture" --original-command "/run-itemized 949")"
run_test "run_itemized_not_misclassified_as_run_item" "yes" "$(
  grep -q 'Run Epic Policy Recommendation' <<< "$itemized_text_output" &&
  ! grep -q 'Run Item Policy Recommendation' <<< "$itemized_text_output" &&
  echo yes || echo no
)"

items_suffix_text_output="$("$HELPER" --scope "$backlog_fixture" --original-command "/run-itemsX 949")"
run_test "run_items_suffix_not_misclassified_as_run_items" "yes" "$(
  grep -q 'Run Epic Policy Recommendation' <<< "$items_suffix_text_output" &&
  ! grep -q 'Run Items Policy Recommendation' <<< "$items_suffix_text_output" &&
  echo yes || echo no
)"

run_items_output="$("$HELPER" --scope "$backlog_fixture" --original-command "/run-items 949 950" --json)"
run_test "run_items_copy_paste_uses_run_items" "yes" "$(
  run_items_copy_paste="$(printf '%s\n' "$run_items_output" | jq -r '.copyPasteCommand')"
  if grep -Fq -- '/run-items 949' <<<"$run_items_copy_paste" &&
    ! grep -Fq -- "\$run-epic" <<<"$run_items_copy_paste"; then
    echo yes
  else
    echo no
  fi
)"

items_list_fixture="$(write_fixture items-list "$(jq '.itemInput = "949,950"' "$backlog_fixture")")"
items_list_output="$("$HELPER" --scope "$items_list_fixture" --original-command "/run-items 949 950" --json)"
run_test "run_items_copy_paste_space_separates_items" "yes" "$(
  printf '%s\n' "$items_list_output" | jq -r '.copyPasteCommand' | grep -Fq -- '/run-items 949 950' && echo yes || echo no
)"

PATH="$MOCK_BIN:$PATH" "$HELPER" --scope "$backlog_fixture" --original-command "\$run-epic issues 949" --json >/dev/null
run_test "does_not_call_gh_or_git" "0" "$(wc -l < "$CALL_LOG" | tr -d ' ')"

schema_fixture="$(write_fixture schema '{
  "scopeSource": "items",
  "epicNumber": null,
  "itemInput": "200",
  "baseBranch": "develop",
  "baseAmbiguous": false,
  "baseReason": "no integration branch label",
  "policy": {"delegateReview": false, "mayMerge": false, "mayStartBacklog": false, "maxRisk": "low"},
  "groups": {
    "eligible": [{"number": 200, "title": "Add users table database migration", "status": "Backlog", "type": "Feature", "labels": ["database"], "dependencies": {"state": "none"}}],
    "blocked": [],
    "already_merged": [],
    "in_review": [],
    "ambiguous": []
  },
  "items": [
    {"number": 200, "title": "Add users table database migration", "status": "Backlog", "type": "Feature", "labels": ["database"], "dependencies": {"state": "none"}}
  ]
}')"
schema_output="$(recommend_json "$schema_fixture" "\$run-epic --items 200")"
run_test "schema_scope_recommends_plan_checkpoint" "plan:technical" "$(printf '%s\n' "$schema_output" | jq -r '.recommendedPolicy.checkpoints[0] | .stage + ":" + .domain')"
run_test "schema_checkpoint_pending" "pending" "$(printf '%s\n' "$schema_output" | jq -r '.recommendedPolicy.checkpoints[0].satisfaction_state')"
run_test "schema_checkpoint_requires_confirmation" "true" "$(printf '%s\n' "$schema_output" | jq -r '.requiresConfirmation')"
run_test "schema_copy_paste_includes_checkpoint_file" "yes" "$(printf '%s\n' "$schema_output" | jq -r '.copyPasteCommand' | grep -Fq -- '--checkpoints-file checkpoint-policy.json' && echo yes || echo no)"
run_test "schema_checkpoint_reason_names_title_signal" "yes" "$(printf '%s\n' "$schema_output" | jq -r '.recommendedPolicy.checkpoints[0].reason' | grep -Fq "title phrase 'database migration'" && echo yes || echo no)"

generic_data_body_fixture="$(write_fixture generic-data-body '{
  "scopeSource": "items",
  "epicNumber": null,
  "itemInput": "201",
  "baseBranch": "develop",
  "baseAmbiguous": false,
  "baseReason": "no integration branch label",
  "policy": {"delegateReview": false, "mayMerge": false, "mayStartBacklog": false, "maxRisk": "low"},
  "groups": {
    "eligible": [{"number": 201, "title": "Classify transient PostgREST responses", "body": "The response schema includes SQL and database-shaped persistent data in a data model-like payload, but no migration is proposed.", "status": "Plan Ready", "type": "Workflow", "labels": [], "dependencies": {"state": "none"}}],
    "blocked": [],
    "already_merged": [],
    "in_review": [],
    "ambiguous": []
  },
  "items": [
    {"number": 201, "title": "Classify transient PostgREST responses", "body": "The response schema includes SQL and database-shaped persistent data in a data model-like payload, but no migration is proposed.", "status": "Plan Ready", "type": "Workflow", "labels": []}
  ]
}')"
generic_data_body_output="$(recommend_json "$generic_data_body_fixture" "\$run-epic --items 201")"
run_test "generic_data_body_terms_do_not_checkpoint" "0" "$(printf '%s\n' "$generic_data_body_output" | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "plan" and .domain == "technical")] | length')"

resilient_read_fixture="$(write_fixture resilient-read "$(jq '
  .groups.eligible[0].number = 202
  | .groups.eligible[0].title = "resilient-read helper for raw PostgREST transient error classification"
  | .groups.eligible[0].body = "Classifies raw PostgREST responses, transient error shapes, database-facing responses, and schema-shaped payloads without changing tables or persistent data."
  | .items[0] = .groups.eligible[0]
' "$generic_data_body_fixture")")"
resilient_read_output="$(recommend_json "$resilient_read_fixture" "\$run-epic --items 202")"
run_test "resilient_read_body_has_no_data_model_checkpoint" "0" "$(printf '%s\n' "$resilient_read_output" | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "plan" and .domain == "technical")] | length')"

generic_label_fixture="$(write_fixture generic-label "$(jq '
  .groups.eligible[0].number = 203
  | .groups.eligible[0].title = "Tune database-facing report wording"
  | .groups.eligible[0].body = "No migration work."
  | .groups.eligible[0].labels = ["database"]
  | .items[0] = .groups.eligible[0]
' "$generic_data_body_fixture")")"
generic_label_output="$(recommend_json "$generic_label_fixture" "\$run-epic --items 203")"
run_test "generic_database_label_does_not_checkpoint" "0" "$(printf '%s\n' "$generic_label_output" | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "plan" and .domain == "technical")] | length')"

label_signal_fixture="$(write_fixture label-signal "$(jq '
  .groups.eligible[0].number = 204
  | .groups.eligible[0].title = "Prepare release migration runbook"
  | .groups.eligible[0].body = "No extra signal."
  | .groups.eligible[0].labels = ["Database Migration", "schema-change"]
  | .items[0] = .groups.eligible[0]
' "$generic_data_body_fixture")")"
label_signal_output="$(recommend_json "$label_signal_fixture" "\$run-epic --items 204")"
run_test "explicit_migration_labels_checkpoint_with_exact_reason" "yes" "$(printf '%s\n' "$label_signal_output" | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "plan" and .domain == "technical") | .reason' | grep -Fq "label 'Database Migration'; label 'schema-change'" && echo yes || echo no)"

action_title_fixture="$(write_fixture action-title "$(jq '
  .groups.eligible[0].number = 205
  | .groups.eligible[0].title = "Add customer schema column"
  | .groups.eligible[0].body = "Plan-ready implementation."
  | .groups.eligible[0].labels = []
  | .items[0] = .groups.eligible[0]
' "$generic_data_body_fixture")")"
action_title_output="$(recommend_json "$action_title_fixture" "\$run-epic --items 205")"
run_test "action_oriented_schema_title_checkpoints" "yes" "$(printf '%s\n' "$action_title_output" | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "plan" and .domain == "technical") | .reason' | grep -Fq "title phrase 'Add customer schema column'" && echo yes || echo no)"

false_signal_title_fixture="$(write_fixture false-signal-title "$(jq '
  .groups.eligible[0].number = 206
  | .groups.eligible[0].title = "Fix false data-model change signal"
  | .groups.eligible[0].body = "The bug is a checkpoint false positive."
  | .items[0] = .groups.eligible[0]
' "$generic_data_body_fixture")")"
false_signal_title_output="$(recommend_json "$false_signal_title_fixture" "\$run-epic --items 206")"
run_test "false_signal_title_does_not_checkpoint" "0" "$(printf '%s\n' "$false_signal_title_output" | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "plan" and .domain == "technical")] | length')"

migration_title_fixture="$(write_fixture migration-title "$(jq '
  .groups.eligible[0].number = 207
  | .groups.eligible[0].title = "Plan database migration rollout"
  | .groups.eligible[0].body = "Plan-ready implementation."
  | .items[0] = .groups.eligible[0]
' "$generic_data_body_fixture")")"
migration_title_output="$(recommend_json "$migration_title_fixture" "\$run-epic --items 207")"
run_test "migration_title_phrases_checkpoint" "yes" "$(printf '%s\n' "$migration_title_output" | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "plan" and .domain == "technical") | .reason' | grep -Fq "title phrase 'database migration'" && echo yes || echo no)"

body_phrase_fixture="$(write_fixture body-phrase "$(jq '
  .groups.eligible[0].number = 208
  | .groups.eligible[0].title = "Apply stored procedure updates"
  | .groups.eligible[0].body = "Use CREATE TABLE for the fixture, ALTER TABLE for the rollout, add a new column, and document the database migration."
  | .items[0] = .groups.eligible[0]
' "$generic_data_body_fixture")")"
body_phrase_output="$(recommend_json "$body_phrase_fixture" "\$run-epic --items 208")"
run_test "migration_body_phrases_checkpoint_with_exact_reason" "yes" "$(printf '%s\n' "$body_phrase_output" | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "plan" and .domain == "technical") | .reason' | grep -Fq "body phrase 'CREATE TABLE'; body phrase 'ALTER TABLE'; body phrase 'new column'; body phrase 'database migration'" && echo yes || echo no)"

lookalike_migration_fixture="$(write_fixture lookalike-migration "$(jq '
  .groups.eligible[0].number = 209
  | .groups.eligible[0].title = "Document SQL vocabulary"
  | .groups.eligible[0].body = "CREATE TABLETOP, ALTER TABLET, a new columnist, and database migration-guide text are not migration evidence."
  | .items[0] = .groups.eligible[0]
' "$generic_data_body_fixture")")"
lookalike_migration_output="$(recommend_json "$lookalike_migration_fixture" "\$run-epic --items 209")"
run_test "migration_phrase_lookalikes_do_not_checkpoint" "0" "$(printf '%s\n' "$lookalike_migration_output" | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "plan" and .domain == "technical")] | length')"

multi_signal_fixture="$(write_fixture multi-signal "$(jq '
  .groups.eligible[0].number = 210
  | .groups.eligible[0].title = "Add account table"
  | .groups.eligible[0].body = "CREATE TABLE accounts. CREATE TABLE accounts."
  | .groups.eligible[0].labels = ["database-migration", "database-migration"]
  | .items[0] = .groups.eligible[0]
' "$generic_data_body_fixture")")"
multi_signal_output="$(recommend_json "$multi_signal_fixture" "\$run-epic --items 210")"
run_test "data_model_signals_are_ordered_and_deduplicated" "data-model checkpoint matched label 'database-migration'; title phrase 'Add account table'; body phrase 'CREATE TABLE'" "$(printf '%s\n' "$multi_signal_output" | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "plan" and .domain == "technical") | .reason')"

variant_item_output="$(recommend_json "$schema_fixture" "/run-item 200")"
variant_items_output="$(recommend_json "$schema_fixture" "/run-items 200 201")"
variant_epic_output="$(recommend_json "$schema_fixture" "\$run-epic --items 200")"
run_test "bounded_command_variants_share_data_model_classifier" "yes" "$(
  item_reason="$(printf '%s\n' "$variant_item_output" | jq -r '.recommendedPolicy.checkpoints[0].reason')"
  items_reason="$(printf '%s\n' "$variant_items_output" | jq -r '.recommendedPolicy.checkpoints[0].reason')"
  epic_reason="$(printf '%s\n' "$variant_epic_output" | jq -r '.recommendedPolicy.checkpoints[0].reason')"
  [ "$item_reason" = "$items_reason" ] && [ "$items_reason" = "$epic_reason" ] && echo yes || echo no
)"

sensitive_fixture="$(write_fixture sensitive '{
  "scopeSource": "items",
  "epicNumber": null,
  "itemInput": "300",
  "baseBranch": "develop",
  "baseAmbiguous": false,
  "baseReason": "no integration branch label",
  "policy": {"delegateReview": false, "mayMerge": false, "mayStartBacklog": false, "maxRisk": "low"},
  "groups": {
    "eligible": [],
    "blocked": [],
    "already_merged": [],
    "in_review": [{"number": 300, "title": "Harden auth permission checks", "status": "Development in Review", "type": "Feature", "labels": []}],
    "ambiguous": []
  },
  "items": [
    {"number": 300, "title": "Harden auth permission checks", "status": "Development in Review", "type": "Feature", "labels": [], "group": "in_review"}
  ]
}')"
sensitive_output="$(recommend_json "$sensitive_fixture" "\$run-epic --items 300")"
run_test "sensitive_scope_recommends_implementation_checkpoint" "implementation:technical" "$(printf '%s\n' "$sensitive_output" | jq -r '.recommendedPolicy.checkpoints[0] | .stage + ":" + .domain')"

sensitive_backlog_fixture="$(write_fixture sensitive-backlog '{
  "scopeSource": "items",
  "epicNumber": null,
  "itemInput": "301",
  "baseBranch": "develop",
  "baseAmbiguous": false,
  "baseReason": "no integration branch label",
  "policy": {"delegateReview": false, "mayMerge": false, "mayStartBacklog": false, "maxRisk": "low"},
  "groups": {
    "eligible": [{"number": 301, "title": "Add account controls", "body": "Must handle auth permissions before delegated merge.", "status": "Backlog", "type": "Feature", "labels": []}],
    "blocked": [],
    "already_merged": [],
    "in_review": [],
    "ambiguous": []
  },
  "items": [
    {"number": 301, "title": "Add account controls", "body": "Must handle auth permissions before delegated merge.", "status": "Backlog", "type": "Feature", "labels": []}
  ]
}')"
sensitive_backlog_output="$(recommend_json "$sensitive_backlog_fixture" "\$run-epic --items 301")"
run_test "sensitive_backlog_recommends_implementation_checkpoint" "implementation:technical" "$(printf '%s\n' "$sensitive_backlog_output" | jq -r '.recommendedPolicy.checkpoints[0] | .stage + ":" + .domain')"

# Regression coverage for issue #1504: the security-checkpoint keyword test must
# use word boundaries so ordinary vocabulary ("authoring", "author", "authority",
# "insensitive") no longer trips a spurious implementation checkpoint, while real
# security/auth terms still do. security_case_fixture derives each case from the
# in_review "sensitive_fixture" so only the implementation/technical checkpoint is
# exercised.
security_case_fixture() {
  if [ "$#" -ne 4 ]; then
    printf 'ERROR: security_case_fixture requires exactly 4 arguments; got %s\n' "$#" >&2
    return 2
  fi
  local name="$1" number="$2" title="$3" body="$4"
  write_fixture "$name" "$(jq --argjson number "$number" --arg title "$title" --arg body "$body" '
    .groups.in_review[0].number = $number
    | .groups.in_review[0].title = $title
    | .groups.in_review[0].body = $body
    | .items[0] = .groups.in_review[0]
  ' "$sensitive_fixture")"
}
security_case_checkpoint_count() {
  if [ "$#" -ne 2 ]; then
    printf 'ERROR: security_case_checkpoint_count requires exactly 2 arguments; got %s\n' "$#" >&2
    return 2
  fi
  local fixture="$1" number="$2"
  recommend_json "$fixture" "\$run-epic --items $number" \
    | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "implementation" and .domain == "technical")] | length'
}
security_case_checkpoint_reason() {
  if [ "$#" -ne 2 ]; then
    printf 'ERROR: security_case_checkpoint_reason requires exactly 2 arguments; got %s\n' "$#" >&2
    return 2
  fi
  local fixture="$1" number="$2"
  recommend_json "$fixture" "\$run-epic --items $number" \
    | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "implementation" and .domain == "technical") | .reason'
}

# False-positive corpus: must NOT trigger the security checkpoint. Confirmed
# against the unfixed regex (test("auth|security|secret|permission|credential|
# sensitive")) that every one of these words matches as a bare substring before
# this fix, which is exactly the defect being regression-tested here.
authoring_fixture="$(security_case_fixture authoring-fp 320 "Improve plan-authoring guidance" "Related: #1496 (Protocol 02 plan-authoring rigor) has no bearing here.")"
run_test "authoring_word_does_not_checkpoint" "0" "$(security_case_checkpoint_count "$authoring_fixture" 320)"

author_fixture="$(security_case_fixture author-fp 321 "Credit the documentation author" "The author of this guide should be listed in the footer.")"
run_test "author_word_does_not_checkpoint" "0" "$(security_case_checkpoint_count "$author_fixture" 321)"

authority_fixture="$(security_case_fixture authority-fp 322 "Clarify service authority boundaries" "This service has no authority over billing decisions.")"
run_test "authority_word_does_not_checkpoint" "0" "$(security_case_checkpoint_count "$authority_fixture" 322)"

insensitive_fixture="$(security_case_fixture insensitive-fp 323 "Make string comparison case insensitive" "The comparison should be case insensitive for usernames.")"
run_test "insensitive_word_does_not_checkpoint" "0" "$(security_case_checkpoint_count "$insensitive_fixture" 323)"

# True-positive corpus: must still trigger the security checkpoint.
authentication_fixture="$(security_case_fixture authentication-tp 324 "Add authentication to login flow" "Users must authenticate before accessing the dashboard.")"
run_test "authentication_word_still_checkpoints" "1" "$(security_case_checkpoint_count "$authentication_fixture" 324)"

authorization_fixture="$(security_case_fixture authorization-tp 325 "Fix authorization checks" "The authorization check for admin routes is missing.")"
run_test "authorization_word_still_checkpoints" "1" "$(security_case_checkpoint_count "$authorization_fixture" 325)"

secret_fixture="$(security_case_fixture secret-tp 326 "Rotate leaked secret" "The leaked secret must be rotated immediately.")"
run_test "secret_word_still_checkpoints" "1" "$(security_case_checkpoint_count "$secret_fixture" 326)"

credential_fixture="$(security_case_fixture credential-tp 327 "Store credential in vault" "The credential should be stored in a secrets vault.")"
run_test "credential_word_still_checkpoints" "1" "$(security_case_checkpoint_count "$credential_fixture" 327)"
run_test "security_checkpoint_reason_names_matched_term_and_line" "yes" "$(security_case_checkpoint_reason "$credential_fixture" 327 | grep -Fq "keyword 'credential' in line: \"The credential should be stored in a secrets vault.\"" && echo yes || echo no)"

# "un-" negated auth terms are real security vocabulary ("unauthorized access",
# "unauthenticated request") that the pre-fix bare-substring regex also matched
# (via "auth" inside them). The word-boundary fix must not introduce a false
# negative here just because "un" glues directly onto the stem.
unauthorized_fixture="$(security_case_fixture unauthorized-tp 328 "Reject unauthorized requests" "Return 403 for unauthorized access to the admin API.")"
run_test "unauthorized_word_still_checkpoints" "1" "$(security_case_checkpoint_count "$unauthorized_fixture" 328)"

unauthenticated_fixture="$(security_case_fixture unauthenticated-tp 329 "Block unauthenticated calls" "Middleware should reject unauthenticated requests before hitting the handler.")"
run_test "unauthenticated_word_still_checkpoints" "1" "$(security_case_checkpoint_count "$unauthenticated_fixture" 329)"

run_test "docs_scope_has_no_checkpoints" "0" "$(printf '%s\n' "$docs_output" | jq -r '.recommendedPolicy.checkpoints | length')"

complete_criteria_fixture="$(write_fixture complete-criteria '{
  "scopeSource": "items",
  "epicNumber": null,
  "itemInput": "401",
  "baseBranch": "develop",
  "baseAmbiguous": false,
  "baseReason": "no integration branch label",
  "policy": {"delegateReview": false, "mayMerge": false, "mayStartBacklog": false, "maxRisk": "low"},
  "groups": {
    "eligible": [{"number": 401, "title": "Add clear workflow report labels", "body": "## Problem\nThe report is hard to scan.\n\n## Acceptance Criteria\n- The report labels each proposed item.\n- The report names held items.\n", "status": "Backlog", "type": "Workflow", "labels": [], "dependencies": {"state": "none"}}],
    "blocked": [],
    "already_merged": [],
    "in_review": [],
    "ambiguous": []
  },
  "items": [
    {"number": 401, "title": "Add clear workflow report labels", "body": "## Problem\nThe report is hard to scan.\n\n## Acceptance Criteria\n- The report labels each proposed item.\n- The report names held items.\n", "status": "Backlog", "type": "Workflow", "labels": []}
  ]
}')"
complete_criteria_output="$(recommend_json "$complete_criteria_fixture" "\$run-epic --items 401")"
run_test "complete_acceptance_criteria_has_no_product_checkpoint" "0" "$(printf '%s\n' "$complete_criteria_output" | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "spec" and .domain == "product")] | length')"

# Sibling classifier audit (issue #1504): the unresolved-product signal shared the
# same bare-alternation defect as the security test ("ambiguous" is a substring of
# "unambiguous"). "unambiguous" must not trigger the spec/product checkpoint,
# while a genuine "ambiguous" reference still does.
unambiguous_fixture="$(write_fixture unambiguous "$(jq '
  .groups.eligible[0].body = "## Problem\nThis flow is unambiguous and fully specified.\n\n## Acceptance Criteria\n- The report labels each proposed item.\n- The report names held items.\n"
  | .items[0].body = .groups.eligible[0].body
' "$complete_criteria_fixture")")"
unambiguous_output="$(recommend_json "$unambiguous_fixture" "\$run-epic --items 401")"
run_test "unambiguous_word_does_not_recommend_product_checkpoint" "0" "$(printf '%s\n' "$unambiguous_output" | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "spec" and .domain == "product")] | length')"

ambiguous_fixture_word="$(write_fixture ambiguous-word "$(jq '
  .groups.eligible[0].body = "## Problem\nThis flow is ambiguous in edge cases.\n\n## Acceptance Criteria\n- The report labels each proposed item.\n- The report names held items.\n"
  | .items[0].body = .groups.eligible[0].body
' "$complete_criteria_fixture")")"
ambiguous_output_word="$(recommend_json "$ambiguous_fixture_word" "\$run-epic --items 401")"
run_test "ambiguous_word_still_recommends_product_checkpoint" "issue signals unresolved product requirements or acceptance-criteria ambiguity" "$(printf '%s\n' "$ambiguous_output_word" | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "spec" and .domain == "product") | .reason')"

case_variant_fixture="$(write_fixture case-variant "$(jq '.groups.eligible[0].body = "## ACCEPTANCE CRITERIA\n- The heading case is normalized.\n" | .items[0].body = .groups.eligible[0].body' "$complete_criteria_fixture")")"
case_variant_output="$(recommend_json "$case_variant_fixture" "\$run-epic --items 401")"
run_test "acceptance_criteria_heading_case_variants_are_normal_structure" "0" "$(printf '%s\n' "$case_variant_output" | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "spec" and .domain == "product")] | length')"

empty_criteria_fixture="$(write_fixture empty-criteria "$(jq '.groups.eligible[0].body = "## Acceptance Criteria\n\n## Notes\nMore detail later.\n" | .items[0].body = .groups.eligible[0].body' "$complete_criteria_fixture")")"
empty_criteria_output="$(recommend_json "$empty_criteria_fixture" "\$run-epic --items 401")"
run_test "empty_acceptance_criteria_recommends_product_checkpoint" "empty acceptance criteria" "$(printf '%s\n' "$empty_criteria_output" | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "spec" and .domain == "product") | .reason')"

colon_empty_criteria_fixture="$(write_fixture colon-empty-criteria "$(jq '.groups.eligible[0].body = "## Acceptance Criteria:\n\n## Notes\nMore detail later.\n" | .items[0].body = .groups.eligible[0].body' "$complete_criteria_fixture")")"
colon_empty_criteria_output="$(recommend_json "$colon_empty_criteria_fixture" "\$run-epic --items 401")"
run_test "empty_acceptance_criteria_heading_with_colon_recommends_product_checkpoint" "empty acceptance criteria" "$(printf '%s\n' "$colon_empty_criteria_output" | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "spec" and .domain == "product") | .reason')"

placeholder_criteria_fixture="$(write_fixture placeholder-criteria "$(jq '.groups.eligible[0].body = "## Acceptance Criteria\n- TBD\n- To be defined\n" | .items[0].body = .groups.eligible[0].body' "$complete_criteria_fixture")")"
placeholder_criteria_output="$(recommend_json "$placeholder_criteria_fixture" "\$run-epic --items 401")"
run_test "placeholder_acceptance_criteria_recommends_product_checkpoint" "placeholder acceptance criteria" "$(printf '%s\n' "$placeholder_criteria_output" | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "spec" and .domain == "product") | .reason')"

nested_placeholder_fixture="$(write_fixture nested-placeholder "$(jq '.groups.eligible[0].body = "## Acceptance Criteria\n### Required behavior\n- TBD\n" | .items[0].body = .groups.eligible[0].body' "$complete_criteria_fixture")")"
nested_placeholder_output="$(recommend_json "$nested_placeholder_fixture" "\$run-epic --items 401")"
run_test "nested_acceptance_criteria_heading_placeholder_recommends_checkpoint" "placeholder acceptance criteria" "$(printf '%s\n' "$nested_placeholder_output" | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "spec" and .domain == "product") | .reason')"

nested_complete_fixture="$(write_fixture nested-complete "$(jq '.groups.eligible[0].body = "## Acceptance Criteria\n### Required behavior\n- The user can run the bounded prelude.\n" | .items[0].body = .groups.eligible[0].body' "$complete_criteria_fixture")")"
nested_complete_output="$(recommend_json "$nested_complete_fixture" "\$run-epic --items 401")"
run_test "nested_acceptance_criteria_heading_with_real_criteria_is_complete" "0" "$(printf '%s\n' "$nested_complete_output" | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "spec" and .domain == "product")] | length')"

open_question_fixture="$(write_fixture open-question "$(jq '.groups.eligible[0].body = "## Problem\nOpen question: should this apply to epics too?\n\n## Acceptance Criteria\n- The report labels each proposed item.\n" | .items[0].body = .groups.eligible[0].body' "$complete_criteria_fixture")")"
open_question_output="$(recommend_json "$open_question_fixture" "\$run-epic --items 401")"
run_test "populated_criteria_with_open_question_still_recommends_checkpoint" "issue signals unresolved product requirements or acceptance-criteria ambiguity" "$(printf '%s\n' "$open_question_output" | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "spec" and .domain == "product") | .reason')"

lookalike_fixture="$(write_fixture lookalike "$(jq '.groups.eligible[0].body = "The acceptance criteria are listed below.\n\n## Acceptance Criteria\n- The populated list is enough.\n" | .items[0].body = .groups.eligible[0].body' "$complete_criteria_fixture")")"
lookalike_output="$(recommend_json "$lookalike_fixture" "\$run-epic --items 401")"
run_test "acceptance_criteria_phrase_in_complete_body_is_not_checkpoint_signal" "0" "$(printf '%s\n' "$lookalike_output" | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "spec" and .domain == "product")] | length')"

duplicate_heading_fixture="$(write_fixture duplicate-heading "$(jq '.groups.eligible[0].body = "## Acceptance Criteria\n\n## Acceptance Criteria\n- The later repeated heading has real criteria.\n" | .items[0].body = .groups.eligible[0].body' "$complete_criteria_fixture")")"
duplicate_heading_output="$(recommend_json "$duplicate_heading_fixture" "\$run-epic --items 401")"
run_test "duplicate_acceptance_criteria_heading_before_content_is_not_empty_section" "0" "$(printf '%s\n' "$duplicate_heading_output" | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "spec" and .domain == "product")] | length')"

second_empty_fixture="$(write_fixture second-empty "$(jq '.groups.eligible[0].body = "## Acceptance Criteria\n- First section is complete.\n\n## Acceptance Criteria\n\n## Notes\nSecond section is empty.\n" | .items[0].body = .groups.eligible[0].body' "$complete_criteria_fixture")")"
second_empty_output="$(recommend_json "$second_empty_fixture" "\$run-epic --items 401")"
run_test "second_empty_acceptance_criteria_section_recommends_checkpoint" "empty acceptance criteria" "$(printf '%s\n' "$second_empty_output" | jq -r '.recommendedPolicy.checkpoints[] | select(.stage == "spec" and .domain == "product") | .reason')"

plan_stage_criteria_fixture="$(write_fixture plan-stage-criteria "$(jq '.groups.eligible[0].status = "Plan Ready" | .items[0].status = "Plan Ready"' "$empty_criteria_fixture")")"
plan_stage_criteria_output="$(recommend_json "$plan_stage_criteria_fixture" "\$run-epic --items 401")"
run_test "plan_stage_acceptance_criteria_body_does_not_create_spec_checkpoint" "0" "$(printf '%s\n' "$plan_stage_criteria_output" | jq -r '[.recommendedPolicy.checkpoints[]? | select(.stage == "spec" and .domain == "product")] | length')"

waived_file="$TMP_ROOT/waived-checkpoints.json"
printf '%s\n' '[{
  "item_number": 200,
  "stage": "plan",
  "domain": "technical",
  "reason": "schema change is additive only",
  "required_human_action": "review and approve proposed data model in the plan before implementation proceeds",
  "satisfaction_state": "waived",
  "waiver_rationale": "schema change is additive only and pre-approved in epic brief"
}]' > "$waived_file"
waived_output="$("$HELPER" --scope "$schema_fixture" --original-command "\$run-epic --items 200" --checkpoints-file "$waived_file" --json)"
run_test "explicit_checkpoint_override_source" "explicit" "$(printf '%s\n' "$waived_output" | jq -r '.fieldSources.checkpoints')"
run_test "waived_checkpoint_preserved" "waived" "$(printf '%s\n' "$waived_output" | jq -r '.effectivePolicy.checkpoints[0].satisfaction_state')"
run_test "checkpoint_policy_audit_fields_present" "yes" "$(printf '%s\n' "$waived_output" | jq -e '.checkpointPolicy.recommended and .checkpointPolicy.selected and .checkpointPolicy.effective' >/dev/null && echo yes || echo no)"

satisfied_file="$TMP_ROOT/satisfied-checkpoints.json"
printf '%s\n' '[{
  "item_number": 200,
  "stage": "plan",
  "domain": "technical",
  "reason": "human-approved migration plan",
  "required_human_action": "review and approve proposed data model in the plan before implementation proceeds",
  "satisfaction_state": "satisfied",
  "satisfied_by": "workflow operator",
  "satisfaction_evidence": "approved in implementation handoff"
}]' > "$satisfied_file"
satisfied_output="$("$HELPER" --scope "$schema_fixture" --original-command "\$run-epic --items 200" --checkpoints-file "$satisfied_file" --json)"
run_test "satisfied_checkpoint_preserved" "satisfied:human-approved migration plan" "$(printf '%s\n' "$satisfied_output" | jq -r '.effectivePolicy.checkpoints[0] | .satisfaction_state + ":" + .reason')"

invalid_waived_file="$TMP_ROOT/invalid-waived.json"
printf '%s\n' '[{"item_number": 200, "stage": "plan", "domain": "technical", "satisfaction_state": "waived"}]' > "$invalid_waived_file"
run_fails_contains "rejects_waived_without_rationale" "waived checkpoints require waiver_rationale" "$HELPER" --scope "$schema_fixture" --original-command x --checkpoints-file "$invalid_waived_file" --json

invalid_state_file="$TMP_ROOT/invalid-state-checkpoints.json"
printf '%s\n' '[{"item_number": 200, "stage": "plan", "domain": "technical", "satisfaction_state": "pendng"}]' > "$invalid_state_file"
run_fails_contains "rejects_unknown_checkpoint_satisfaction_state" "checkpoint satisfaction_state must be one of: pending, satisfied, waived" "$HELPER" --scope "$schema_fixture" --original-command x --checkpoints-file "$invalid_state_file" --json

empty_checkpoints_file="$TMP_ROOT/empty-checkpoints.json"
printf '%s\n' '[]' > "$empty_checkpoints_file"
empty_override_output="$("$HELPER" --scope "$schema_fixture" --original-command "\$run-epic --items 200" --checkpoints-file "$empty_checkpoints_file" --json)"
run_test "empty_checkpoint_override_keeps_recommended" "1" "$(printf '%s\n' "$empty_override_output" | jq -r '.effectivePolicy.checkpoints | length')"
run_test "empty_checkpoint_override_source_remains_recommended" "recommended" "$(printf '%s\n' "$empty_override_output" | jq -r '.fieldSources.checkpoints')"
run_test "empty_checkpoint_override_still_requires_confirmation" "true" "$(printf '%s\n' "$empty_override_output" | jq -r '.requiresConfirmation')"

checkpoint_text_output="$("$HELPER" --scope "$schema_fixture" --original-command "\$run-epic --items 200")"
run_test "text_output_lists_checkpoints" "yes" "$(grep -q 'Human checkpoints' <<< "$checkpoint_text_output" && echo yes || echo no)"

blocked_schema_fixture="$(write_fixture blocked-schema "$(jq '
  .groups.eligible = []
  | .groups.blocked = [.items[0] | .group = "blocked" | .dependencies.state = "blocked"]
  | .items[0].group = "blocked"
  | .items[0].dependencies.state = "blocked"
' "$schema_fixture")")"
blocked_schema_output="$(recommend_json "$blocked_schema_fixture" "\$run-epic --items 200")"
run_test "blocked_item_skips_checkpoint_recommendation" "0" "$(printf '%s\n' "$blocked_schema_output" | jq -r '.recommendedPolicy.checkpoints | length')"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
