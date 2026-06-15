#!/usr/bin/env bash
# test-run-epic-policy-recommender.sh - Unit tests for /run-epic policy recommendation.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir)"
case "$GIT_COMMON_DIR" in
  /*) REPO_ROOT="$(cd "$GIT_COMMON_DIR/.." && pwd -P)" ;;
  *) REPO_ROOT="$(cd "$SCRIPT_DIR/$GIT_COMMON_DIR/.." && pwd -P)" ;;
esac
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
run_test "explicit_policy_skips_confirmation" "false" "$(printf '%s\n' "$explicit_output" | jq -r '.requiresConfirmation')"
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

PATH="$MOCK_BIN:$PATH" "$HELPER" --scope "$backlog_fixture" --original-command "\$run-epic issues 949" --json >/dev/null
run_test "does_not_call_gh_or_git" "0" "$(wc -l < "$CALL_LOG" | tr -d ' ')"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
