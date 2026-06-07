#!/usr/bin/env bash
# test-workflow-lib-github-projects.sh — Unit tests for GitHub Projects helpers.
#
# Exercises issue #824's rate-limit fix:
#   1. get_tracker_status_for_issue uses targeted issue->projectItems GraphQL
#   2. ensure_on_project_board checks membership without full-board pagination
#   3. update_tracker_status_best_effort resolves item/status IDs without item-list
#   4. Type helpers read/update project Type and discover open Workflow items
#
# Usage: bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

MOCK_BIN="$(mktemp -d)"
CALL_LOG="$(mktemp)"

_harness_exit() {
  local status=$?
  rm -rf "$MOCK_BIN"
  rm -f "$CALL_LOG"
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
  "repo view --json owner --jq .owner.login")
    printf 'lhpaul\n'
    ;;
  "repo view --json name --jq .name")
    printf 'ai-dev-framework-template\n'
    ;;
  *"api graphql"* )
    case "$*" in
      *"projectV2(number:"*)
        cat <<'JSON'
{"data":{"user":{"projectV2":{"id":"PVT_project_1"}},"organization":null}}
JSON
        ;;
	      *"projectItems(first:"*)
	        if [ "${MOCK_PROJECT_ITEM_MODE:-existing}" = "missing" ]; then
	          cat <<'JSON'
	{"data":{"repository":{"issue":{"projectItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
	        elif [ "${MOCK_PROJECT_ITEM_MODE:-existing}" = "paginated" ]; then
	          case "$*" in
	            *"after=cursor_page_1"*)
	              cat <<'JSON'
	{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_item_824","project":{"id":"PVT_project_1","number":1},"status":{"name":"Spec Ready"},"type":{"name":"Workflow"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
	              ;;
	            *)
	              cat <<'JSON'
	{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_other","project":{"id":"PVT_other","number":99},"status":{"name":"Backlog"},"type":{"name":"Bug"}}],"pageInfo":{"hasNextPage":true,"endCursor":"cursor_page_1"}}}}}}
JSON
	              ;;
	          esac
	        else
	          cat <<'JSON'
	{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_item_824","project":{"id":"PVT_project_1","number":1},"status":{"name":"Spec Ready"},"type":{"name":"Workflow"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
	        fi
	        ;;
      *"fields(first:"*)
        if [ "${MOCK_STATUS_FIELD_MODE:-existing}" = "graphql_fail" ]; then
          printf 'GraphQL failure\n' >&2
          exit 42
        elif [ "${MOCK_STATUS_FIELD_MODE:-existing}" = "invalid_json" ]; then
          printf 'not json\n'
        elif [ "${MOCK_STATUS_FIELD_MODE:-existing}" = "paginated" ]; then
          case "$*" in
            *"after=cursor_field_1"*)
              cat <<'JSON'
{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status","options":[{"id":"OPT_spec_ready","name":"Spec Ready"},{"id":"OPT_in_development","name":"In Development"}]},{"id":"PVTSSF_type","name":"Type","options":[{"id":"OPT_workflow","name":"Workflow"},{"id":"OPT_bug","name":"Bug"},{"id":"OPT_refactor","name":"Refactor"},{"id":"OPT_feature","name":"Feature"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
JSON
              ;;
            *)
              cat <<'JSON'
{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_other","name":"Priority","options":[{"id":"OPT_high","name":"High"}]}],"pageInfo":{"hasNextPage":true,"endCursor":"cursor_field_1"}}}}}
JSON
              ;;
          esac
        else
          cat <<'JSON'
{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status","options":[{"id":"OPT_spec_ready","name":"Spec Ready"},{"id":"OPT_in_development","name":"In Development"}]},{"id":"PVTSSF_type","name":"Type","options":[{"id":"OPT_workflow","name":"Workflow"},{"id":"OPT_bug","name":"Bug"},{"id":"OPT_refactor","name":"Refactor"},{"id":"OPT_feature","name":"Feature"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
JSON
        fi
        ;;
      *"updateProjectV2ItemFieldValue"*)
        cat <<'JSON'
{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"PVTI_item_824"}}}}
JSON
        ;;
      *)
        printf '{}\n'
        ;;
    esac
    ;;
  "issue list --repo lhpaul/ai-dev-framework-template --state open --limit 1000 --json number,title,labels,createdAt,url")
    cat <<'JSON'
[{"number":824,"title":"Workflow helper issue","labels":[],"createdAt":"2026-06-04T00:00:00Z","url":"https://github.com/lhpaul/ai-dev-framework-template/issues/824"},{"number":825,"title":"Bug helper issue","labels":[],"createdAt":"2026-06-04T01:00:00Z","url":"https://github.com/lhpaul/ai-dev-framework-template/issues/825"}]
JSON
    ;;
  "project item-list 1 --owner lhpaul --limit 1000 --format json")
    cat <<'JSON'
{"items":[{"content":{"number":824},"status":"Backlog","priority":"High","type":"Workflow","title":"Workflow helper issue"},{"content":{"number":825},"status":"Backlog","priority":"High","type":"Bug","title":"Bug helper issue"},{"content":{"number":826},"status":"Merged","priority":"High","type":"Workflow","title":"Closed workflow helper issue"}]}
JSON
    ;;
  "project item-add "*)
    printf 'PVTI_added\n'
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

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"

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
    echo "FAIL: $name — expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

forbidden_project_reads() {
  awk '/project (item-list|view|field-list)/ { print }' "$CALL_LOG"
}

count_log_matches() {
  local pattern="$1"
  awk -v pattern="$pattern" '$0 ~ pattern { count += 1 } END { print count + 0 }' "$CALL_LOG"
}

reset_log() {
  : > "$CALL_LOG"
}

echo ""
echo "=== GitHub Projects targeted lookup helpers ==="

reset_log
status="$(get_tracker_status_for_issue 824)"
run_test "targeted_status_read" "Spec Ready" "$status"
run_test "status_read_avoids_full_board_scan" "" "$(forbidden_project_reads)"

reset_log
tracker_type="$(get_tracker_type_for_issue 824)"
run_test "targeted_type_read" "Workflow" "$tracker_type"
run_test "type_read_avoids_full_board_scan" "" "$(forbidden_project_reads)"

reset_log
export MOCK_PROJECT_ITEM_MODE=paginated
status="$(get_tracker_status_for_issue 824)"
unset MOCK_PROJECT_ITEM_MODE
run_test "targeted_status_read_paginates" "Spec Ready" "$status"
run_test "paginated_status_uses_two_item_queries" "2" "$(count_log_matches 'projectItems')"
run_test "paginated_status_avoids_full_board_scan" "" "$(forbidden_project_reads)"

reset_log
invalid_item="$(workflow_github_project_item_for_issue "not-a-number" "1" 2>/dev/null)"
run_test "invalid_issue_number_returns_empty" "" "$invalid_item"
run_test "invalid_issue_number_avoids_graphql" "0" "$(count_log_matches 'api graphql')"

reset_log
membership_output="$(ensure_on_project_board 824 "In Development")"
case "$membership_output" in
  *"already on project board"*) membership_result="already-present" ;;
  *) membership_result="$membership_output" ;;
esac
run_test "membership_existing_detected" "already-present" "$membership_result"
run_test "membership_check_avoids_full_board_scan" "" "$(forbidden_project_reads)"
run_test "membership_existing_does_not_add" "0" "$(count_log_matches 'project item-add')"

reset_log
export MOCK_PROJECT_ITEM_MODE=missing
membership_output="$(ensure_on_project_board 824 "In Development")"
unset MOCK_PROJECT_ITEM_MODE
case "$membership_output" in
  *"added to project board"*) membership_result="added" ;;
  *) membership_result="$membership_output" ;;
esac
run_test "membership_missing_adds_issue" "added" "$membership_result"
run_test "membership_missing_avoids_full_board_scan" "" "$(forbidden_project_reads)"
run_test "membership_missing_adds_once" "1" "$(count_log_matches 'project item-add')"

reset_log
update_output="$(update_tracker_status_best_effort 824 "In Development" "Spec Ready")"
case "$update_output" in
  *"Updating tracker status for issue #824 to 'In Development'"*) update_result="updated" ;;
  *) update_result="$update_output" ;;
esac
run_test "status_update_runs" "updated" "$update_result"
run_test "status_update_avoids_full_board_scan" "" "$(forbidden_project_reads)"
run_test "status_update_mutates_project_item" "1" "$(count_log_matches 'api graphql' | awk '{print ($1 >= 3) ? 1 : 0}')"

reset_log
export MOCK_STATUS_FIELD_MODE=paginated
update_output="$(update_tracker_status_best_effort 824 "In Development" "Spec Ready")"
unset MOCK_STATUS_FIELD_MODE
case "$update_output" in
  *"Updating tracker status for issue #824 to 'In Development'"*) update_result="updated" ;;
  *) update_result="$update_output" ;;
esac
run_test "status_update_field_lookup_paginates" "updated" "$update_result"
run_test "status_update_field_lookup_uses_two_field_queries" "2" "$(count_log_matches 'fields')"
run_test "status_update_field_lookup_avoids_full_board_scan" "" "$(forbidden_project_reads)"

reset_log
type_update_output="$(update_tracker_type_best_effort 824 "Workflow")"
case "$type_update_output" in
  *"Updating tracker Type for issue #824 to 'Workflow'"*) type_update_result="updated" ;;
  *) type_update_result="$type_update_output" ;;
esac
run_test "type_update_runs" "updated" "$type_update_result"
run_test "type_update_avoids_full_board_scan" "" "$(forbidden_project_reads)"
run_test "type_update_mutates_project_item" "1" "$(count_log_matches 'api graphql' | awk '{print ($1 >= 3) ? 1 : 0}')"

reset_log
__workflow_project_type_field_cache_project_id=""
__workflow_project_type_field_cache_json=""
export MOCK_STATUS_FIELD_MODE=graphql_fail
type_field_output=""
type_field_exit=0
type_field_output="$(workflow_github_project_type_field_json "PVT_project_1" 2>/dev/null)" || type_field_exit=$?
unset MOCK_STATUS_FIELD_MODE
run_test "type_field_graphql_failure_returns_nonzero" "1" "$type_field_exit"
run_test "type_field_graphql_failure_empty_output" "" "$type_field_output"
run_test "type_field_graphql_failure_no_cache" "" "$__workflow_project_type_field_cache_json"

reset_log
__workflow_project_type_field_cache_project_id=""
__workflow_project_type_field_cache_json=""
export MOCK_STATUS_FIELD_MODE=invalid_json
type_update_output="$(update_tracker_type_best_effort 824 "Workflow" 2>&1)"
unset MOCK_STATUS_FIELD_MODE
case "$type_update_output" in
  *"could not read project Type field metadata"*) type_update_result="metadata-failed" ;;
  *) type_update_result="$type_update_output" ;;
esac
run_test "type_update_metadata_parse_failure_warns" "metadata-failed" "$type_update_result"
run_test "type_update_metadata_parse_failure_no_mutation" "0" "$(count_log_matches 'updateProjectV2ItemFieldValue')"

reset_log
workflow_issues="$(list_open_workflow_type_issues)"
workflow_issue_numbers="$(printf '%s' "$workflow_issues" | jq -r '.[].number' | tr '\n' ' ' | sed 's/ $//')"
run_test "workflow_type_discovery_filters_open_type" "824" "$workflow_issue_numbers"
run_test "workflow_type_discovery_uses_single_board_scan" "1" "$(count_log_matches 'project item-list')"

reset_log
workflow_github_project_item_for_issue() {
  printf 'not json'
}
type_update_output="$(update_tracker_type_best_effort 824 "Workflow" 2>&1)"
case "$type_update_output" in
  *"could not parse project item ID"*) type_update_result="item-parse-failed" ;;
  *) type_update_result="$type_update_output" ;;
esac
run_test "type_update_item_parse_failure_warns" "item-parse-failed" "$type_update_result"
run_test "type_update_item_parse_failure_no_mutation" "0" "$(count_log_matches 'updateProjectV2ItemFieldValue')"

echo ""
echo "Test summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
