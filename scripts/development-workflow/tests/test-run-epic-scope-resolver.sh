#!/usr/bin/env bash
# test-run-epic-scope-resolver.sh - Unit tests for the read-only /run-epic resolver.
#
# Usage: bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/development-workflow/run-epic-scope-resolver.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/gh-calls.log"
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

_harness_exit() {
  local status=$?
  rm -rf "$TMP_ROOT"
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _harness_exit EXIT

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"

case "$*" in
  auth\ status)
    exit 0
    ;;
  repo\ view\ --json\ nameWithOwner\ --jq\ .nameWithOwner)
    printf 'lhpaul/ai-dev-framework-template\n'
    ;;
  issue\ edit*|pr\ create*|pr\ merge*|project\ item-edit*|project\ item-add*)
    printf 'mutating gh command was called: gh %s\n' "$*" >&2
    exit 99
    ;;
  *'mutation'*)
    printf 'mutating GraphQL operation was called: gh %s\n' "$*" >&2
    exit 99
    ;;
  api\ graphql*)
    case "$*" in
      *'projectV2(number:'*)
        cat <<'JSON'
{"data":{"user":{"projectV2":{"id":"PVT_project_1"}},"organization":null}}
JSON
        ;;
      *'projectItems(first:'*)
        issue_number="$(printf '%s\n' "$*" | sed -n 's/.*issueNumber=\([0-9][0-9]*\).*/\1/p')"
        status="Backlog"
        type="Workflow"
        case "$issue_number" in
          102) status="Plan in Review" ;;
          103) status="Merged" ;;
          104) status="Backlog" ;;
          105) status="Backlog" ;;
          106) status="Backlog" ;;
          *) status="Backlog" ;;
        esac
        jq -n --arg status "$status" --arg type "$type" '{
          data: {repository: {issue: {projectItems: {
            nodes: [{id: "PVTI_item", project: {id: "PVT_project_1", number: 1}, status: {name: $status}, type: {name: $type}}],
            pageInfo: {hasNextPage: false, endCursor: null}
          }}}}
        }'
        ;;
      *'subIssues(first:'*)
        if [ "${MOCK_EPIC_MODE:-populated}" = "empty" ]; then
          cat <<'JSON'
{"data":{"repository":{"issue":{"number":900,"title":"Empty epic","subIssues":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
        else
          cat <<'JSON'
{"data":{"repository":{"issue":{"number":900,"title":"Epic","subIssues":{"nodes":[{"number":101,"title":"One","state":"OPEN"},{"number":102,"title":"Two","state":"OPEN"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
        fi
        ;;
      *'parent { number title }'*)
        child="$(printf '%s\n' "$*" | sed -n 's/.*number=\([0-9][0-9]*\).*/\1/p')"
        jq -n --argjson child "$child" '{data:{repository:{issue:{number:$child,parent:{number:900,title:"Epic"}}}}}'
        ;;
      *)
        printf 'unexpected gh graphql invocation: gh %s\n' "$*" >&2
        exit 64
        ;;
    esac
    ;;
  issue\ view\ *\ --json\ number,title,state,body,labels,projectItems)
    issue_number="${3}"
    title="Issue ${issue_number}"
    state="OPEN"
    body=""
    labels_json='[]'
    case "$issue_number" in
      101) labels_json='[{"name":"integration-branch:delegated-epic-orchestration"}]' ;;
      102) labels_json='[{"name":"integration-branch:delegated-epic-orchestration"}]' ;;
      103) labels_json='[{"name":"integration-branch:delegated-epic-orchestration"}]' ;;
      104) body='Depends on #103'; labels_json='[{"name":"integration-branch:delegated-epic-orchestration"}]' ;;
      105) labels_json='[{"name":"integration-branch:alpha"}]' ;;
      106) labels_json='[{"name":"integration-branch:beta"}]' ;;
    esac
    jq -n \
      --argjson number "$issue_number" \
      --arg title "$title" \
      --arg state "$state" \
      --arg body "$body" \
      --argjson labels "$labels_json" \
      '{number:$number,title:$title,state:$state,body:$body,labels:$labels,projectItems:[{priority:{name:"High"}}]}'
    ;;
  issue\ view\ *\ --json\ number,title,state)
    issue_number="${3}"
    state="OPEN"
    [ "$issue_number" = "103" ] && state="CLOSED"
    jq -n --argjson number "$issue_number" --arg state "$state" \
      '{number:$number,title:("Dependency " + ($number|tostring)),state:$state}'
    ;;
  pr\ list\ --state\ open*)
    search_number="$(printf '%s\n' "$*" | sed -n 's/.*--search \([0-9][0-9]*\).*/\1/p')"
    if [ "$search_number" = "102" ]; then
      cat <<'JSON'
[{"number":2102,"title":"Plan PR","headRefName":"implementation-plan/102-two","baseRefName":"develop-delegated-epic-orchestration","isDraft":false,"labels":[{"name":"ready-for-human-review"}]}]
JSON
    else
      printf '[]\n'
    fi
    ;;
  pr\ list\ --state\ merged*)
    search_number="$(printf '%s\n' "$*" | sed -n 's/.*--search \([0-9][0-9]*\).*/\1/p')"
    if [ "$search_number" = "101" ]; then
      cat <<'JSON'
[{"number":2101,"title":"Merged plan PR","headRefName":"implementation-plan/101-one","baseRefName":"develop-delegated-epic-orchestration","mergedAt":"2026-06-12T11:00:00Z"}]
JSON
    elif [ "$search_number" = "103" ]; then
      cat <<'JSON'
[{"number":2103,"title":"Merged PR","headRefName":"feature/103-three","baseRefName":"develop-delegated-epic-orchestration","mergedAt":"2026-06-12T12:00:00Z"}]
JSON
    else
      printf '[]\n'
    fi
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"

export PATH="$MOCK_BIN:$PATH"
export MOCK_GH_CALL_LOG="$CALL_LOG"
export GITHUB_PROJECT_OWNER="lhpaul"
export GITHUB_PROJECT_NUMBER="1"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1"
  local expected="$2"
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

run_json() {
  "$RESOLVER" "$@" --json
}

echo ""
echo "=== Run epic scope resolver ==="

run_fails_contains "requires_scope" "pass exactly one of --epic or --items" "$RESOLVER"
run_fails_contains "rejects_both_scope_inputs" "not both" "$RESOLVER" --epic 900 --items 101
run_fails_contains "rejects_invalid_items" "not a positive integer" "$RESOLVER" --items "101,nope"
run_fails_contains "rejects_empty_item_token" "contains an empty item" "$RESOLVER" --items "101,,102"

items_output="$(run_json --items 101,101,102)"
run_test "explicit_items_deduped" "2" "$(printf '%s\n' "$items_output" | jq '.items | length')"
run_test "explicit_items_no_expansion" "101,102" "$(printf '%s\n' "$items_output" | jq -r '[.items[].number] | join(",")')"
run_test "shared_integration_label_base" "develop-delegated-epic-orchestration" "$(printf '%s\n' "$items_output" | jq -r '.baseBranch')"
run_test "merged_plan_pr_not_complete" "eligible" "$(printf '%s\n' "$items_output" | jq -r '.items[] | select(.number == 101) | .group')"
run_test "in_review_group_detected" "102" "$(printf '%s\n' "$items_output" | jq -r '.groups.in_review[0].number')"

override_output="$(run_json --items 105,106 --base develop-custom)"
run_test "base_override_wins" "develop-custom" "$(printf '%s\n' "$override_output" | jq -r '.baseBranch')"
run_test "base_override_keeps_eligible" "2" "$(printf '%s\n' "$override_output" | jq '.groups.eligible | length')"

ambiguous_output="$(run_json --items 105,106)"
run_test "conflicting_labels_no_base" "" "$(printf '%s\n' "$ambiguous_output" | jq -r '.baseBranch')"
run_test "conflicting_labels_ambiguous" "2" "$(printf '%s\n' "$ambiguous_output" | jq '.groups.ambiguous | length')"

dependency_output="$(run_json --items 104)"
run_test "satisfied_dependency_not_blocked" "eligible" "$(printf '%s\n' "$dependency_output" | jq -r '.items[0].group')"

merged_output="$(run_json --items 103)"
run_test "merged_pr_group_detected" "already_merged" "$(printf '%s\n' "$merged_output" | jq -r '.items[0].group')"

epic_output="$(run_json --epic 900)"
run_test "epic_subissues_resolved" "101,102" "$(printf '%s\n' "$epic_output" | jq -r '[.items[].number] | join(",")')"

empty_output="$(MOCK_EPIC_MODE=empty run_json --epic 900)"
run_test "empty_epic_reports_scope" "true" "$(printf '%s\n' "$empty_output" | jq -r '.emptyEpicScope')"
run_test "json_read_only_guarantee" "yes" "$(
  printf '%s\n' "$items_output" | jq -e '.readOnlyGuarantee | test("No tracker status")' >/dev/null && echo yes || echo no
)"
run_test "no_mutating_gh_commands" "no" "$(
  grep -Eq '(^issue edit|^pr create|^pr merge|^project item-edit|^project item-add|mutation)' "$CALL_LOG" && echo yes || echo no
)"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
