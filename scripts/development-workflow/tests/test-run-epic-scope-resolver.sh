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

# _config_backup / _config_file track any temporary .ai-dev-workflow.yaml swap
# made during provider-normalization tests. _harness_exit restores the file on
# any exit so a set -e abort cannot leave the repo config permanently clobbered.
_config_file="$REPO_ROOT/.ai-dev-workflow.yaml"
_config_backup=""

_harness_exit() {
  local status=$?
  # Restore .ai-dev-workflow.yaml if it was swapped out during provider tests.
  if [ -n "$_config_backup" ] && [ -f "$_config_backup" ]; then
    cp "$_config_backup" "$_config_file"
  fi
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
        if [[ "$*" == *"after= -f"* ]]; then
          printf 'empty pagination cursor was passed\n' >&2
          exit 64
        fi
        if [ "${MOCK_EPIC_MODE:-populated}" = "missing" ]; then
          cat <<'JSON'
{"data":{"repository":{"issue":null}}}
JSON
        elif [ "${MOCK_EPIC_MODE:-populated}" = "empty" ]; then
          cat <<'JSON'
{"data":{"repository":{"issue":{"number":900,"title":"Empty epic","subIssues":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
        elif [ "${MOCK_EPIC_MODE:-populated}" = "paginated" ]; then
          if [[ "$*" == *"after=cursor_page_1"* ]]; then
            cat <<'JSON'
{"data":{"repository":{"issue":{"number":900,"title":"Epic","subIssues":{"nodes":[{"number":102,"title":"Two","state":"OPEN"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
          else
            cat <<'JSON'
{"data":{"repository":{"issue":{"number":900,"title":"Epic","subIssues":{"nodes":[{"number":101,"title":"One","state":"OPEN"}],"pageInfo":{"hasNextPage":true,"endCursor":"cursor_page_1"}}}}}}
JSON
          fi
        else
          cat <<'JSON'
{"data":{"repository":{"issue":{"number":900,"title":"Epic","subIssues":{"nodes":[{"number":101,"title":"One","state":"OPEN"},{"number":102,"title":"Two","state":"OPEN"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
        fi
        ;;
      *'parent { number title }'*)
        child="$(printf '%s\n' "$*" | sed -n 's/.*number=\([0-9][0-9]*\).*/\1/p')"
        parent=900
        [ "${MOCK_PARENT_MODE:-valid}" = "mismatch" ] && parent=901
        jq -n --argjson child "$child" --argjson parent "$parent" \
          '{data:{repository:{issue:{number:$child,parent:{number:$parent,title:"Epic"}}}}}'
        ;;
      *)
        printf 'unexpected gh graphql invocation: gh %s\n' "$*" >&2
        exit 64
        ;;
    esac
    ;;
  issue\ view\ *\ --json\ number,title,state,stateReason,body,labels,projectItems)
    issue_number="${3}"
    title="Issue ${issue_number}"
    state="OPEN"
    state_reason=""
    body=""
    labels_json='[]'
    case "$issue_number" in
      101) labels_json='[{"name":"integration-branch:delegated-epic-orchestration"}]' ;;
      102) labels_json='[{"name":"integration-branch:delegated-epic-orchestration"}]' ;;
      103) labels_json='[{"name":"integration-branch:delegated-epic-orchestration"}]' ;;
      104) body='Depends on #103'; labels_json='[{"name":"integration-branch:delegated-epic-orchestration"}]' ;;
      105) labels_json='[{"name":"integration-branch:alpha"}]' ;;
      106) labels_json='[{"name":"integration-branch:beta"}]' ;;
      107) body='Depends on #108'; labels_json='[{"name":"integration-branch:delegated-epic-orchestration"}]' ;;
      109) state="CLOSED"; state_reason="NOT_PLANNED"; labels_json='[{"name":"integration-branch:delegated-epic-orchestration"}]' ;;
      110) labels_json='[{"name":"integration-branch:delegated-epic-orchestration"}]' ;;
      111) body='Blocked by #108'; labels_json='[{"name":"integration-branch:delegated-epic-orchestration"}]' ;;
    esac
    jq -n \
      --argjson number "$issue_number" \
      --arg title "$title" \
      --arg state "$state" \
      --arg stateReason "$state_reason" \
      --arg body "$body" \
      --argjson labels "$labels_json" \
      '{number:$number,title:$title,state:$state,stateReason:$stateReason,body:$body,labels:$labels,projectItems:[{priority:{name:"High"}}]}'
    ;;
  issue\ view\ *\ --json\ number,title,state)
    issue_number="${3}"
    state="OPEN"
    [ "$issue_number" = "103" ] && state="CLOSED"
    jq -n --argjson number "$issue_number" --arg state "$state" \
      '{number:$number,title:("Dependency " + ($number|tostring)),state:$state}'
    ;;
  api\ --paginate\ --slurp\ repos/lhpaul/ai-dev-framework-template/pulls\?state=open\&per_page=100)
    cat <<'JSON'
[[{"number":2102,"title":"Plan PR","head":{"ref":"implementation-plan/102-two"},"base":{"ref":"develop-delegated-epic-orchestration"},"draft":false,"labels":[{"name":"ready-for-human-review"}],"merged_at":null},{"number":2110,"title":"Unready PR","head":{"ref":"feature/110-ten"},"base":{"ref":"develop-delegated-epic-orchestration"},"draft":false,"labels":[],"merged_at":null}]]
JSON
    ;;
  api\ --paginate\ --slurp\ repos/lhpaul/ai-dev-framework-template/pulls\?state=closed\&per_page=100)
    cat <<'JSON'
[[{"number":2101,"title":"Merged plan PR","head":{"ref":"implementation-plan/101-one"},"base":{"ref":"develop-delegated-epic-orchestration"},"draft":false,"labels":[],"merged_at":"2026-06-12T11:00:00Z"},{"number":2103,"title":"Merged PR","head":{"ref":"feature/103-three"},"base":{"ref":"develop-delegated-epic-orchestration"},"draft":false,"labels":[],"merged_at":"2026-06-12T12:00:00Z"},{"number":2104,"title":"Closed unmerged PR","head":{"ref":"feature/104-four"},"base":{"ref":"develop-delegated-epic-orchestration"},"draft":false,"labels":[],"merged_at":null}]]
JSON
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
run_fails_contains "rejects_invalid_may_start_backlog" "--may-start-backlog must be true or false" "$RESOLVER" --items 101 --may-start-backlog maybe
run_fails_contains "rejects_invalid_max_risk" "--max-risk must be one of low, medium, or high" "$RESOLVER" --items 101 --max-risk blocked
run_fails_contains "rejects_flag_as_may_start_backlog_value" "--may-start-backlog requires a value" "$RESOLVER" --items 101 --may-start-backlog --json
run_fails_contains "rejects_flag_as_max_risk_value" "--max-risk requires a value" "$RESOLVER" --items 101 --max-risk --json
run_fails_contains "missing_epic_clear_error" "not found or inaccessible" env MOCK_EPIC_MODE=missing "$RESOLVER" --epic 900
run_fails_contains "parent_mismatch_rejected" "does not point back" env MOCK_PARENT_MODE=mismatch "$RESOLVER" --epic 900

items_output="$(run_json --items 101,101,102 --delegate-review --may-merge --may-start-backlog true --max-risk medium)"
run_test "explicit_items_deduped" "2" "$(printf '%s\n' "$items_output" | jq '.items | length')"
run_test "explicit_items_no_expansion" "101,102" "$(printf '%s\n' "$items_output" | jq -r '[.items[].number] | join(",")')"
run_test "policy_delegate_review" "true" "$(printf '%s\n' "$items_output" | jq -r '.policy.delegateReview')"
run_test "policy_may_merge" "true" "$(printf '%s\n' "$items_output" | jq -r '.policy.mayMerge')"
run_test "policy_may_start_backlog" "true" "$(printf '%s\n' "$items_output" | jq -r '.policy.mayStartBacklog')"
run_test "policy_max_risk" "medium" "$(printf '%s\n' "$items_output" | jq -r '.policy.maxRisk')"
run_test "shared_integration_label_base" "develop-delegated-epic-orchestration" "$(printf '%s\n' "$items_output" | jq -r '.baseBranch')"
run_test "merged_plan_pr_not_complete" "eligible" "$(printf '%s\n' "$items_output" | jq -r '.items[] | select(.number == 101) | .group')"
run_test "in_review_group_detected" "102" "$(printf '%s\n' "$items_output" | jq -r '.groups.in_review[0].number')"

text_output="$("$RESOLVER" --items 101 --delegate-review --may-start-backlog false --max-risk high)"
run_test "text_policy_includes_delegate_review" "yes" "$(grep -q 'Delegated review: true' <<< "$text_output" && echo yes || echo no)"
run_test "text_policy_includes_backlog_policy" "yes" "$(grep -q 'May start Backlog: false' <<< "$text_output" && echo yes || echo no)"
run_test "text_policy_includes_max_risk" "yes" "$(grep -q 'Max risk: high' <<< "$text_output" && echo yes || echo no)"

override_output="$(run_json --items 105,106 --base develop-custom)"
run_test "base_override_wins" "develop-custom" "$(printf '%s\n' "$override_output" | jq -r '.baseBranch')"
run_test "base_override_keeps_eligible" "2" "$(printf '%s\n' "$override_output" | jq '.groups.eligible | length')"

ambiguous_output="$(run_json --items 105,106)"
run_test "conflicting_labels_no_base" "null" "$(printf '%s\n' "$ambiguous_output" | jq -r '.baseBranch')"
run_test "conflicting_labels_base_ambiguous" "true" "$(printf '%s\n' "$ambiguous_output" | jq -r '.baseAmbiguous')"
run_test "conflicting_labels_ambiguous" "2" "$(printf '%s\n' "$ambiguous_output" | jq '.groups.ambiguous | length')"

dependency_output="$(run_json --items 104)"
run_test "satisfied_dependency_not_blocked" "eligible" "$(printf '%s\n' "$dependency_output" | jq -r '.items[0].group')"
run_test "resolver_items_include_issue_body" "Depends on #103" "$(printf '%s\n' "$dependency_output" | jq -r '.items[0].body')"

blocked_output="$(run_json --items 107)"
run_test "blocked_dependency_group_detected" "blocked" "$(printf '%s\n' "$blocked_output" | jq -r '.items[0].group')"

blocked_variant_output="$(run_json --items 111)"
run_test "blocked_dependency_variant_detected" "blocked" "$(printf '%s\n' "$blocked_variant_output" | jq -r '.items[0].group')"

merged_output="$(run_json --items 103)"
run_test "merged_pr_group_detected" "already_merged" "$(printf '%s\n' "$merged_output" | jq -r '.items[0].group')"

unready_pr_output="$(run_json --items 110)"
run_test "unready_open_pr_remains_eligible" "eligible" "$(printf '%s\n' "$unready_pr_output" | jq -r '.items[0].group')"

closed_output="$(run_json --items 109)"
run_test "closed_not_planned_not_complete" "ambiguous" "$(printf '%s\n' "$closed_output" | jq -r '.items[0].group')"

epic_output="$(run_json --epic 900)"
run_test "epic_subissues_resolved" "101,102" "$(printf '%s\n' "$epic_output" | jq -r '[.items[].number] | join(",")')"

paginated_output="$(MOCK_EPIC_MODE=paginated run_json --epic 900)"
run_test "epic_pagination_resolved" "101,102" "$(printf '%s\n' "$paginated_output" | jq -r '[.items[].number] | join(",")')"

empty_output="$(MOCK_EPIC_MODE=empty run_json --epic 900)"
run_test "empty_epic_reports_scope" "true" "$(printf '%s\n' "$empty_output" | jq -r '.emptyEpicScope')"
run_test "json_read_only_guarantee" "yes" "$(
  printf '%s\n' "$items_output" | jq -e '.readOnlyGuarantee | test("No tracker status")' >/dev/null && echo yes || echo no
)"
run_test "no_mutating_gh_commands" "no" "$(
  grep -Eq '(^issue edit|^pr create|^pr merge|^project item-edit|^project item-add|mutation)' "$CALL_LOG" && echo yes || echo no
)"

echo ""
echo "=== Provider normalization and deferred-read signals (#966) ==="

# Text-output mode (no --json) emits PROVIDER= and TRACKER_READ_DEFERRED= lines.
# Temporarily swap .ai-dev-workflow.yaml to test non-default providers.
# _harness_exit() restores the real config on any exit.
_config_backup="$TMP_ROOT/ai-dev-workflow.yaml.bak"
cp "$_config_file" "$_config_backup"

# --- github_projects provider ---
# The real config already has github_projects; run text-mode and verify PROVIDER=.
github_text_output="$("$RESOLVER" --items 101 2>/dev/null)"
case "$github_text_output" in
  *"PROVIDER=github_projects"*) github_provider_result="emitted" ;;
  *) github_provider_result="missing" ;;
esac
run_test "text_output_emits_provider_github_projects" "emitted" "$github_provider_result"

# TRACKER_READ_DEFERRED must NOT appear for github_projects.
case "$github_text_output" in
  *"TRACKER_READ_DEFERRED"*) github_deferred_result="leaked" ;;
  *) github_deferred_result="not-present" ;;
esac
run_test "github_provider_no_tracker_read_deferred" "not-present" "$github_deferred_result"

echo ""
echo "=== Repository mode base-routing context ==="

# --- workflow_hub base-routing context ---
cat > "$_config_file" <<'WORKFLOW_HUB_CONFIG'
schema_version: 2
mode: workflow_hub
issue_tracker:
  provider: github_projects
WORKFLOW_HUB_CONFIG

hub_output="$(run_json --items 101,102)"
run_test "workflow_hub_mode_reported" "workflow_hub" "$(printf '%s\n' "$hub_output" | jq -r '.workflowMode')"
run_test "workflow_hub_base_applies_to_product" "product_implementation_prs" "$(printf '%s\n' "$hub_output" | jq -r '.baseBranchAppliesTo')"
run_test "workflow_hub_base_note_blocks_hub_validation" "yes" "$(
  printf '%s\n' "$hub_output" | jq -e '.baseBranchValidationNote | test("do not validate this base against the hub remote")' >/dev/null && echo yes || echo no
)"

hub_text_output="$("$RESOLVER" --items 101 --delegate-review --may-start-backlog false --max-risk high)"
run_test "text_output_includes_workflow_mode" "yes" "$(grep -q 'Workflow mode: workflow_hub' <<< "$hub_text_output" && echo yes || echo no)"
run_test "text_output_includes_base_context" "yes" "$(grep -q 'Base applies to: product_implementation_prs' <<< "$hub_text_output" && echo yes || echo no)"

# --- single_repo base-routing context ---
cat > "$_config_file" <<'SINGLE_REPO_CONFIG'
schema_version: 2
mode: single_repo
issue_tracker:
  provider: github_projects
SINGLE_REPO_CONFIG

single_repo_output="$(run_json --items 101)"
run_test "single_repo_mode_reported" "single_repo" "$(printf '%s\n' "$single_repo_output" | jq -r '.workflowMode')"
run_test "single_repo_base_applies_to_current_repo" "current_repository_prs" "$(printf '%s\n' "$single_repo_output" | jq -r '.baseBranchAppliesTo')"
run_test "single_repo_base_note_keeps_repo_validation" "yes" "$(
  printf '%s\n' "$single_repo_output" | jq -e '.baseBranchValidationNote | test("Validate the resolved base branch")' >/dev/null && echo yes || echo no
)"

# --- linear provider ---
cat > "$_config_file" <<'LINEAR_CONFIG'
schema_version: 2
issue_tracker:
  provider: linear
LINEAR_CONFIG

linear_text_output="$("$RESOLVER" --items 101 2>/dev/null)"

# Restore immediately; _harness_exit is the safety net.
cp "$_config_backup" "$_config_file"

case "$linear_text_output" in
  *"PROVIDER=linear"*) linear_provider_result="emitted" ;;
  *) linear_provider_result="missing" ;;
esac
run_test "text_output_emits_provider_linear" "emitted" "$linear_provider_result"

# TRACKER_READ_DEFERRED=yes must appear for linear.
case "$linear_text_output" in
  *"TRACKER_READ_DEFERRED=yes"*) linear_deferred_result="emitted" ;;
  *) linear_deferred_result="missing" ;;
esac
run_test "linear_provider_emits_tracker_read_deferred" "emitted" "$linear_deferred_result"

# TRACKER_READ_DEFERRED must appear BEFORE the human-readable header line.
case "$linear_text_output" in
  *"TRACKER_READ_DEFERRED=yes"*"Run Epic Scope Resolver"*)
    deferred_before_header="yes" ;;
  *) deferred_before_header="no" ;;
esac
run_test "tracker_read_deferred_before_human_header" "yes" "$deferred_before_header"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
