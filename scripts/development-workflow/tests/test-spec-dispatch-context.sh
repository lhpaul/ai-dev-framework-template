#!/usr/bin/env bash
# test-spec-dispatch-context.sh - Unit tests for spec dispatch relationship context.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/spec-dispatch-context.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
mkdir -p "$MOCK_BIN"
trap 'rm -rf "$TMP_ROOT"' EXIT

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash

if [ "$1" != "issue" ] || [ "$2" != "view" ]; then
  echo "unexpected gh invocation: $*" >&2
  exit 64
fi

issue="$3"

case "$issue" in
  100)
    cat <<'JSON'
{"number":100,"title":"Internal public-site component unit stages","body":"Build unit stages as an internal state switcher within one public site component instance.","comments":[{"body":"Decision: the selected item uses one component instance with an internal switcher.","url":"https://example.test/comments/1"},{"body":"We still have indecision around naming, but no settled outcome here.","url":"https://example.test/comments/2"}]}
JSON
    ;;
  101)
    cat <<'JSON'
{"number":101,"title":"Multiple public-site component instances","body":"Allow multiple instances of the same public site component type in the catalog.","comments":[]}
JSON
    ;;
  102)
    cat <<'JSON'
{"number":102,"title":"Dependent public-site component catalog","body":"This depends on #100 because the catalog needs the selected unit-stage output first.","comments":[]}
JSON
    ;;
  103)
    cat <<'JSON'
{"number":103,"title":"Coupled public-site component schema","body":"Coordinate shared public site component schema behavior with the selected work before writing acceptance criteria.","comments":[]}
JSON
    ;;
  104)
    cat <<'JSON'
{"number":104,"title":"Negative dependency lookalike public-site component","body":"This requires clarification, not #100. It shares public site component language but does not name a prerequisite.","comments":[]}
JSON
    ;;
  108)
    cat <<'JSON'
{"number":108,"title":"Negated blocked-by public-site component","body":"This is not blocked by #100. It shares public site component language but can proceed independently.","comments":[]}
JSON
    ;;
  109)
    cat <<'JSON'
{"number":109,"title":"Mixed dependency public-site component","body":"This depends on #100 for the API layer. It is not related to #100 for the UI layer.","comments":[]}
JSON
    ;;
  110)
    cat <<'JSON'
{"number":110,"title":"Independent public-site component content","body":"This independent public site component content can proceed alone.","comments":[]}
JSON
    ;;
  111)
    cat <<'JSON'
{"number":111,"title":"Dependent-on public-site component","body":"This is dependent on #100 for the selected unit-stage output.","comments":[]}
JSON
    ;;
  112)
    cat <<'JSON'
{"number":112,"title":"Coupled public-site component validation","body":"Coordinate shared public site component validation behavior with the selected work before writing acceptance criteria.","comments":[]}
JSON
    ;;
  113)
    cat <<'JSON'
{"number":113,"title":"Clarification public-site component","body":"This requires clarification for public site component copy, but does not name another issue.","comments":[]}
JSON
    ;;
  114)
    cat <<'JSON'
{"number":114,"title":"Remote blocker","body":"Different words only.","comments":[{"body":"Decision: this depends on #100 for the selected output.","url":"https://example.test/comments/114"}]}
JSON
    ;;
  115)
    cat <<'JSON'
{"number":115,"title":"Different-target public-site component","body":"This depends on #200, but is not related to #100. It shares public site component wording.","comments":[]}
JSON
    ;;
  116)
    cat <<'JSON'
{"number":116,"title":"Negated sentence public-site component","body":"This does not depend on #100, but it requires #100 discussion notes. It shares public site component wording.","comments":[]}
JSON
    ;;
  117)
    cat <<'JSON'
{"number":117,"title":"Prerequisite public-site component","body":"This has prerequisite #100 before the public site component can proceed.","comments":[]}
JSON
    ;;
  118)
    cat <<'JSON'
{"number":118,"title":"Without public-site component","body":"This cannot proceed without #100 for the public site component.","comments":[]}
JSON
    ;;
  107)
    cat <<'JSON'
{"number":107,"title":"Larger issue reference public-site component","body":"This depends on #2100 for unrelated public site component catalog work.","comments":[]}
JSON
    ;;
  105)
    cat <<'JSON'
{"number":105,"title":"Workflow helper alpha","body":"Tighten helper behavior.","comments":[]}
JSON
    ;;
  106)
    cat <<'JSON'
{"number":106,"title":"Workflow runner beta","body":"Document runner behavior.","comments":[]}
JSON
    ;;
  *)
    echo "unknown issue $issue" >&2
    exit 1
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"

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

orthogonal_output="$("$HELPER" --selected 100 --items 100,101 --json)"
run_test "orthogonal_overlap_outcome" "Orthogonal" "$(printf '%s\n' "$orthogonal_output" | jq -r '.relationships[0].outcome')"
run_test "orthogonal_not_blocking" "false" "$(printf '%s\n' "$orthogonal_output" | jq -r '.blocking')"
run_test "issue_comment_decision_included" "yes" "$(printf '%s\n' "$orthogonal_output" | jq -r '.confirmedDecisions[0].summary | test("internal switcher") | if . then "yes" else "no" end')"
run_test "comment_decision_substring_ignored" "1" "$(printf '%s\n' "$orthogonal_output" | jq -r '.confirmedDecisions | length')"

decision_file="$TMP_ROOT/decisions.jsonl"
printf '%s\n' '{"issue":100,"summary":"Human confirmed this is one component instance.","source":"session"}' > "$decision_file"
decision_output="$("$HELPER" --selected 100 --items 100 --confirmed-decision-file "$decision_file" --json)"
run_test "decision_file_included" "Human confirmed this is one component instance." "$(printf '%s\n' "$decision_output" | jq -r '.confirmedDecisions[] | select(.source == "session") | .summary')"

if "$HELPER" --selected 100 --items 100 --confirmed-decision-file "$TMP_ROOT/missing-decisions.jsonl" --json >/dev/null 2>&1; then
  missing_decision_result="success"
else
  missing_decision_result="failure"
fi
run_test "missing_decision_file_fails" "failure" "$missing_decision_result"

conflicting_decision_file="$TMP_ROOT/conflicting-decisions.jsonl"
{
  printf '%s\n' '{"issue":100,"summary":"Decision: selected work depends on #200.","source":"session"}'
  printf '%s\n' '{"issue":100,"summary":"Decision: selected work is orthogonal to #200.","source":"session"}'
} > "$conflicting_decision_file"
conflicting_decision_output="$("$HELPER" --selected 100 --items 100 --confirmed-decision-file "$conflicting_decision_file" --json)"
run_test "conflicting_decisions_block" "true" "$(printf '%s\n' "$conflicting_decision_output" | jq -r '.blocking')"
run_test "conflicting_decisions_human_action" "yes" "$(printf '%s\n' "$conflicting_decision_output" | jq -r '.humanAction | test("conflicting confirmed decisions") | if . then "yes" else "no" end')"

non_conflicting_decision_file="$TMP_ROOT/non-conflicting-decisions.jsonl"
{
  printf '%s\n' '{"issue":100,"summary":"Decision: selected work is orthogonal to #200.","source":"session"}'
  printf '%s\n' '{"issue":100,"summary":"Follow-up requires more detail before implementation.","source":"session"}'
} > "$non_conflicting_decision_file"
non_conflicting_decision_output="$("$HELPER" --selected 100 --items 100 --confirmed-decision-file "$non_conflicting_decision_file" --json)"
run_test "requires_detail_decision_not_conflict" "false" "$(printf '%s\n' "$non_conflicting_decision_output" | jq -r '.blocking')"

dependent_output="$("$HELPER" --selected 100 --items 100,102 --json)"
run_test "dependent_outcome" "Dependent" "$(printf '%s\n' "$dependent_output" | jq -r '.relationships[0].outcome')"
run_test "dependent_not_blocking" "false" "$(printf '%s\n' "$dependent_output" | jq -r '.blocking')"

dependent_on_output="$("$HELPER" --selected 100 --items 100,111 --json)"
run_test "dependent_on_outcome" "Dependent" "$(printf '%s\n' "$dependent_on_output" | jq -r '.relationships[0].outcome')"
run_test "dependent_on_not_blocking" "false" "$(printf '%s\n' "$dependent_on_output" | jq -r '.blocking')"

prerequisite_output="$("$HELPER" --selected 100 --items 100,117 --json)"
run_test "prerequisite_outcome" "Dependent" "$(printf '%s\n' "$prerequisite_output" | jq -r '.relationships[0].outcome')"
run_test "prerequisite_not_blocking" "false" "$(printf '%s\n' "$prerequisite_output" | jq -r '.blocking')"

without_dependency_output="$("$HELPER" --selected 100 --items 100,118 --json)"
run_test "without_dependency_outcome" "Dependent" "$(printf '%s\n' "$without_dependency_output" | jq -r '.relationships[0].outcome')"
run_test "without_dependency_not_blocking" "false" "$(printf '%s\n' "$without_dependency_output" | jq -r '.blocking')"

orthogonal_override_file="$TMP_ROOT/orthogonal-override.jsonl"
printf '%s\n' '{"issue":100,"summary":"Decision: selected work is orthogonal to #102.","source":"session"}' > "$orthogonal_override_file"
orthogonal_override_output="$("$HELPER" --selected 100 --items 100,102 --confirmed-decision-file "$orthogonal_override_file" --json)"
run_test "orthogonal_decision_overrides_dependency" "Orthogonal" "$(printf '%s\n' "$orthogonal_override_output" | jq -r '.relationships[0].outcome')"
run_test "orthogonal_decision_override_not_blocking" "false" "$(printf '%s\n' "$orthogonal_override_output" | jq -r '.blocking')"

comment_dependency_output="$("$HELPER" --selected 100 --items 100,114 --json)"
run_test "comment_dependency_bypasses_overlap_gate" "Dependent" "$(printf '%s\n' "$comment_dependency_output" | jq -r '.relationships[0].outcome')"
run_test "comment_dependency_not_blocking" "false" "$(printf '%s\n' "$comment_dependency_output" | jq -r '.blocking')"

unclear_output="$("$HELPER" --selected 100 --items 100,103 --json)"
run_test "unclear_outcome" "Unclear" "$(printf '%s\n' "$unclear_output" | jq -r '.relationships[0].outcome')"
run_test "unclear_blocks" "true" "$(printf '%s\n' "$unclear_output" | jq -r '.blocking')"
run_test "unclear_human_action" "yes" "$(printf '%s\n' "$unclear_output" | jq -r '.humanAction | test("Confirm whether") | if . then "yes" else "no" end')"

multi_unclear_output="$("$HELPER" --selected 100 --items 100,103,112 --json)"
run_test "multi_unclear_human_action_includes_first_peer" "yes" "$(printf '%s\n' "$multi_unclear_output" | jq -r '.humanAction | test("#103") | if . then "yes" else "no" end')"
run_test "multi_unclear_human_action_includes_second_peer" "yes" "$(printf '%s\n' "$multi_unclear_output" | jq -r '.humanAction | test("#112") | if . then "yes" else "no" end')"

negative_output="$("$HELPER" --selected 100 --items 100,104 --json)"
run_test "negative_lookalike_not_dependent" "not-dependent" "$(printf '%s\n' "$negative_output" | jq -r 'if .relationships[0].outcome == "Dependent" then "dependent" else "not-dependent" end')"
run_test "negative_lookalike_not_blocking" "false" "$(printf '%s\n' "$negative_output" | jq -r '.blocking')"

negated_dependency_output="$("$HELPER" --selected 100 --items 100,108 --json)"
run_test "negated_dependency_phrase_not_dependent" "not-dependent" "$(printf '%s\n' "$negated_dependency_output" | jq -r 'if .relationships[0].outcome == "Dependent" then "dependent" else "not-dependent" end')"
run_test "negated_dependency_phrase_not_blocking" "false" "$(printf '%s\n' "$negated_dependency_output" | jq -r '.blocking')"

mixed_dependency_output="$("$HELPER" --selected 100 --items 100,109 --json)"
run_test "mixed_dependency_keeps_dependent" "Dependent" "$(printf '%s\n' "$mixed_dependency_output" | jq -r '.relationships[0].outcome')"
run_test "mixed_dependency_not_blocking" "false" "$(printf '%s\n' "$mixed_dependency_output" | jq -r '.blocking')"

different_target_output="$("$HELPER" --selected 100 --items 100,115 --json)"
run_test "different_target_not_dependent" "not-dependent" "$(printf '%s\n' "$different_target_output" | jq -r 'if .relationships[0].outcome == "Dependent" then "dependent" else "not-dependent" end')"
run_test "different_target_not_blocking" "false" "$(printf '%s\n' "$different_target_output" | jq -r '.blocking')"

negated_sentence_output="$("$HELPER" --selected 100 --items 100,116 --json)"
run_test "negated_sentence_not_dependent" "not-dependent" "$(printf '%s\n' "$negated_sentence_output" | jq -r 'if .relationships[0].outcome == "Dependent" then "dependent" else "not-dependent" end')"
run_test "negated_sentence_not_blocking" "false" "$(printf '%s\n' "$negated_sentence_output" | jq -r '.blocking')"

independent_word_output="$("$HELPER" --selected 100 --items 100,110 --json)"
run_test "independent_word_not_unclear" "Orthogonal" "$(printf '%s\n' "$independent_word_output" | jq -r '.relationships[0].outcome')"
run_test "independent_word_not_blocking" "false" "$(printf '%s\n' "$independent_word_output" | jq -r '.blocking')"

bare_requires_output="$("$HELPER" --selected 100 --items 100,113 --json)"
run_test "bare_requires_not_unclear" "Orthogonal" "$(printf '%s\n' "$bare_requires_output" | jq -r '.relationships[0].outcome')"
run_test "bare_requires_not_blocking" "false" "$(printf '%s\n' "$bare_requires_output" | jq -r '.blocking')"

boundary_output="$("$HELPER" --selected 100 --items 100,107 --json)"
run_test "larger_issue_number_not_dependent" "not-dependent" "$(printf '%s\n' "$boundary_output" | jq -r 'if .relationships[0].outcome == "Dependent" then "dependent" else "not-dependent" end')"
run_test "larger_issue_number_not_blocking" "false" "$(printf '%s\n' "$boundary_output" | jq -r '.blocking')"

low_overlap_output="$("$HELPER" --selected 105 --items 105,106 --json)"
run_test "low_impact_overlap_ignored" "0" "$(printf '%s\n' "$low_overlap_output" | jq -r '.relationships | length')"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
