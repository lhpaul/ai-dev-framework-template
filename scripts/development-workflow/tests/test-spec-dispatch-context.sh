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
{"number":100,"title":"Internal public-site component unit stages","body":"Build unit stages as an internal state switcher within one public site component instance.","comments":[{"body":"Decision: the selected item uses one component instance with an internal switcher.","url":"https://example.test/comments/1"}]}
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

decision_file="$TMP_ROOT/decisions.jsonl"
printf '%s\n' '{"issue":100,"summary":"Human confirmed this is one component instance.","source":"session"}' > "$decision_file"
decision_output="$("$HELPER" --selected 100 --items 100 --confirmed-decision-file "$decision_file" --json)"
run_test "decision_file_included" "Human confirmed this is one component instance." "$(printf '%s\n' "$decision_output" | jq -r '.confirmedDecisions[] | select(.source == "session") | .summary')"

dependent_output="$("$HELPER" --selected 100 --items 100,102 --json)"
run_test "dependent_outcome" "Dependent" "$(printf '%s\n' "$dependent_output" | jq -r '.relationships[0].outcome')"
run_test "dependent_not_blocking" "false" "$(printf '%s\n' "$dependent_output" | jq -r '.blocking')"

unclear_output="$("$HELPER" --selected 100 --items 100,103 --json)"
run_test "unclear_outcome" "Unclear" "$(printf '%s\n' "$unclear_output" | jq -r '.relationships[0].outcome')"
run_test "unclear_blocks" "true" "$(printf '%s\n' "$unclear_output" | jq -r '.blocking')"
run_test "unclear_human_action" "yes" "$(printf '%s\n' "$unclear_output" | jq -r '.humanAction | test("Confirm whether") | if . then "yes" else "no" end')"

negative_output="$("$HELPER" --selected 100 --items 100,104 --json)"
run_test "negative_lookalike_not_dependent" "not-dependent" "$(printf '%s\n' "$negative_output" | jq -r 'if .relationships[0].outcome == "Dependent" then "dependent" else "not-dependent" end')"
run_test "negative_lookalike_not_blocking" "false" "$(printf '%s\n' "$negative_output" | jq -r '.blocking')"

negated_dependency_output="$("$HELPER" --selected 100 --items 100,108 --json)"
run_test "negated_dependency_phrase_not_dependent" "not-dependent" "$(printf '%s\n' "$negated_dependency_output" | jq -r 'if .relationships[0].outcome == "Dependent" then "dependent" else "not-dependent" end')"
run_test "negated_dependency_phrase_not_blocking" "false" "$(printf '%s\n' "$negated_dependency_output" | jq -r '.blocking')"

boundary_output="$("$HELPER" --selected 100 --items 100,107 --json)"
run_test "larger_issue_number_not_dependent" "not-dependent" "$(printf '%s\n' "$boundary_output" | jq -r 'if .relationships[0].outcome == "Dependent" then "dependent" else "not-dependent" end')"

low_overlap_output="$("$HELPER" --selected 105 --items 105,106 --json)"
run_test "low_impact_overlap_ignored" "0" "$(printf '%s\n' "$low_overlap_output" | jq -r '.relationships | length')"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
