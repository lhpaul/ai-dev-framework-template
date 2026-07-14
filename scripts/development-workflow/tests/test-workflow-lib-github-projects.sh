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
    if [ "${MOCK_REPO_VIEW_MODE:-ok}" = "fail" ]; then
      exit 42
    fi
    printf 'lhpaul\n'
    ;;
  "repo view --json name --jq .name")
    if [ "${MOCK_REPO_VIEW_MODE:-ok}" = "fail" ]; then
      exit 42
    fi
    printf 'ai-dev-framework-template\n'
    ;;
  "api --paginate --slurp repos/lhpaul/ai-dev-framework-template/milestones?state=all&per_page=100")
    if [ "${MOCK_MILESTONE_MODE:-existing}" = "fail" ]; then
      printf 'milestone list failed\n' >&2
      exit 42
    elif [ "${MOCK_MILESTONE_MODE:-existing}" = "missing" ]; then
      printf '[[]]\n'
    else
      cat <<'JSON'
[[{"number":7,"title":"v1.2.3","state":"open"},{"number":8,"title":"v0.1.0","state":"closed"}]]
JSON
    fi
    ;;
  "api -X POST repos/lhpaul/ai-dev-framework-template/milestones -f title=v1.2.3 -f description=Release v1.2.3")
    if [ "${MOCK_MILESTONE_CREATE_MODE:-ok}" = "fail" ]; then
      printf 'milestone create failed\n' >&2
      exit 42
    fi
    cat <<'JSON'
{"number":9,"title":"v1.2.3","state":"open"}
JSON
    ;;
  "api -X PATCH repos/lhpaul/ai-dev-framework-template/milestones/7 -f state=closed"|"api -X PATCH repos/lhpaul/ai-dev-framework-template/milestones/9 -f state=closed")
    if [ "${MOCK_MILESTONE_CLOSE_MODE:-ok}" = "fail" ]; then
      printf 'milestone close failed\n' >&2
      exit 42
    fi
    cat <<'JSON'
{"number":7,"title":"v1.2.3","state":"closed"}
JSON
    ;;
  "api -X PATCH repos/lhpaul/ai-dev-framework-template/issues/824 -F milestone=7"|"api -X PATCH repos/lhpaul/ai-dev-framework-template/issues/824 -F milestone=9")
    if [ "${MOCK_ISSUE_PATCH_MODE:-ok}" = "fail" ]; then
      printf 'issue patch failed\n' >&2
      exit 42
    fi
    printf '{"number":824,"milestone":{"number":7}}\n'
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
	        elif [ "${MOCK_PROJECT_ITEM_MODE:-existing}" = "legacy_field_value" ]; then
	          cat <<'JSON'
	{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_item_824","project":{"id":"PVT_project_1","number":1},"fieldValueByName":{"name":"Spec Ready"},"type":{"name":"Workflow"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
	        elif [ "${MOCK_PROJECT_ITEM_MODE:-existing}" = "missing_fields" ]; then
	          cat <<'JSON'
	{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_item_824","project":{"id":"PVT_project_1","number":1}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
	        elif [ "${MOCK_PROJECT_ITEM_MODE:-existing}" = "custom_type_only" ]; then
	          cat <<'JSON'
	{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_item_824","project":{"id":"PVT_project_1","number":1},"status":{"name":"Spec Ready"},"customType":{"name":"Workflow"},"type":{"name":"Bug"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
	        elif [ "${MOCK_PROJECT_ITEM_MODE:-existing}" = "configured_type_only" ]; then
	          cat <<'JSON'
	{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_item_824","project":{"id":"PVT_project_1","number":1},"status":{"name":"Spec Ready"},"configuredType":{"name":"Workflow"},"customType":{"name":"Bug"},"type":{"name":"Bug"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
	        elif [ "${MOCK_PROJECT_ITEM_MODE:-existing}" = "released" ]; then
	          cat <<'JSON'
	{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_item_824","project":{"id":"PVT_project_1","number":1},"status":{"name":"Released"},"type":{"name":"Workflow"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
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
        elif [[ "$*" == *"projectId=PVT_project_2"* ]]; then
          cat <<'JSON'
{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_type_project_2","name":"Type","options":[{"id":"OPT_workflow_project_2","name":"Workflow"},{"id":"OPT_bug_project_2","name":"Bug"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
JSON
        elif [ "${MOCK_STATUS_FIELD_MODE:-existing}" = "paginated" ]; then
          case "$*" in
            *"after=cursor_field_1"*)
              cat <<'JSON'
{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status","options":[{"id":"OPT_spec_ready","name":"Spec Ready"},{"id":"OPT_in_development","name":"In Development"},{"id":"OPT_merged","name":"Merged"},{"id":"OPT_released","name":"Released"}]},{"id":"PVTSSF_type","name":"Type","options":[{"id":"OPT_workflow","name":"Workflow"},{"id":"OPT_bug","name":"Bug"},{"id":"OPT_refactor","name":"Refactor"},{"id":"OPT_feature","name":"Feature"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
JSON
              ;;
            *)
              cat <<'JSON'
{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_other","name":"Priority","options":[{"id":"OPT_high","name":"High"}]}],"pageInfo":{"hasNextPage":true,"endCursor":"cursor_field_1"}}}}}
JSON
              ;;
          esac
        elif [ "${MOCK_STATUS_FIELD_MODE:-existing}" = "custom_type_after_type" ]; then
          case "$*" in
            *"after=cursor_field_1"*)
              cat <<'JSON'
{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_custom_type","name":"Custom Type","options":[{"id":"OPT_workflow_custom","name":"Workflow"},{"id":"OPT_bug_custom","name":"Bug"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
JSON
              ;;
            *)
              cat <<'JSON'
{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_type","name":"Type","options":[{"id":"OPT_workflow","name":"Workflow"},{"id":"OPT_bug","name":"Bug"}]}],"pageInfo":{"hasNextPage":true,"endCursor":"cursor_field_1"}}}}}
JSON
              ;;
          esac
        elif [ "${MOCK_STATUS_FIELD_MODE:-existing}" = "configured_type" ]; then
          cat <<'JSON'
{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_custom_type","name":"Custom Type","options":[{"id":"OPT_workflow_custom","name":"Workflow"}]},{"id":"PVTSSF_configured_type","name":"Configured Type","options":[{"id":"OPT_workflow_configured","name":"Workflow"}]},{"id":"PVTSSF_type","name":"Type","options":[{"id":"OPT_workflow","name":"Workflow"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
JSON
        else
          cat <<'JSON'
{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status","options":[{"id":"OPT_spec_ready","name":"Spec Ready"},{"id":"OPT_in_development","name":"In Development"},{"id":"OPT_merged","name":"Merged"},{"id":"OPT_released","name":"Released"}]},{"id":"PVTSSF_type","name":"Type","options":[{"id":"OPT_workflow","name":"Workflow"},{"id":"OPT_bug","name":"Bug"},{"id":"OPT_refactor","name":"Refactor"},{"id":"OPT_feature","name":"Feature"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
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
[{"number":824,"title":"Workflow helper issue","labels":[],"createdAt":"2026-06-04T00:00:00Z","url":"https://github.com/lhpaul/ai-dev-framework-template/issues/824"},{"number":825,"title":"Bug helper issue","labels":[],"createdAt":"2026-06-04T01:00:00Z","url":"https://github.com/lhpaul/ai-dev-framework-template/issues/825"},{"number":826,"title":"Done workflow helper issue","labels":[],"createdAt":"2026-06-04T02:00:00Z","url":"https://github.com/lhpaul/ai-dev-framework-template/issues/826"},{"number":827,"title":"Merged workflow helper issue","labels":[],"createdAt":"2026-06-04T03:00:00Z","url":"https://github.com/lhpaul/ai-dev-framework-template/issues/827"},{"number":828,"title":"Released workflow helper issue","labels":[],"createdAt":"2026-06-04T04:00:00Z","url":"https://github.com/lhpaul/ai-dev-framework-template/issues/828"},{"number":829,"title":"Cancelled workflow helper issue","labels":[],"createdAt":"2026-06-04T05:00:00Z","url":"https://github.com/lhpaul/ai-dev-framework-template/issues/829"}]
JSON
    ;;
  "project item-list 1 --owner lhpaul --limit 1000 --format json")
    cat <<'JSON'
{"items":[{"content":{"number":824},"status":"Backlog","priority":"High","type":"Workflow","title":"Workflow helper issue"},{"content":{"number":825},"status":"Backlog","priority":"High","type":"Bug","title":"Bug helper issue"},{"content":{"number":826},"status":"Done","priority":"High","type":"Workflow","title":"Done workflow helper issue"},{"content":{"number":827},"status":"Merged","priority":"High","type":"Workflow","title":"Merged workflow helper issue"},{"content":{"number":828},"status":"Released","priority":"High","type":"Workflow","title":"Released workflow helper issue"},{"content":{"number":829},"status":"Cancelled","priority":"High","type":"Workflow","title":"Cancelled workflow helper issue"}]}
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

workflow_issue_tracker_provider_raw() {
  printf '%s\n' "${MOCK_TRACKER_PROVIDER:-github_projects}"
}

workflow_issue_tracker_project_number() {
  printf '%s\n' "${MOCK_TRACKER_PROJECT_NUMBER-1}"
}

workflow_issue_tracker_custom_field() {
  case "$1" in
    type_field) printf '%s\n' "${MOCK_TRACKER_TYPE_FIELD:-}" ;;
    *) printf '\n' ;;
  esac
}

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
export MOCK_PROJECT_ITEM_MODE=custom_type_only
tracker_type="$(get_tracker_type_for_issue 824)"
unset MOCK_PROJECT_ITEM_MODE
run_test "targeted_type_read_prefers_custom_type" "Workflow" "$tracker_type"
run_test "custom_type_read_passes_empty_configured_field" "1" "$(count_log_matches 'typeFieldName=')"

reset_log
export MOCK_PROJECT_ITEM_MODE=configured_type_only
export MOCK_TRACKER_TYPE_FIELD="Configured Type"
tracker_type="$(get_tracker_type_for_issue 824)"
unset MOCK_PROJECT_ITEM_MODE
unset MOCK_TRACKER_TYPE_FIELD
run_test "targeted_type_read_prefers_configured_field" "Workflow" "$tracker_type"
run_test "configured_type_read_passes_field_name" "1" "$(count_log_matches 'typeFieldName=Configured Type')"

reset_log
export MOCK_PROJECT_ITEM_MODE=paginated
status="$(get_tracker_status_for_issue 824)"
unset MOCK_PROJECT_ITEM_MODE
run_test "targeted_status_read_paginates" "Spec Ready" "$status"
run_test "paginated_status_uses_two_item_queries" "2" "$(count_log_matches 'projectItems')"
run_test "paginated_status_avoids_full_board_scan" "" "$(forbidden_project_reads)"

reset_log
export MOCK_PROJECT_ITEM_MODE=legacy_field_value
status="$(get_tracker_status_for_issue 824)"
tracker_type="$(get_tracker_type_for_issue 824)"
unset MOCK_PROJECT_ITEM_MODE
run_test "legacy_field_value_status_fallback" "Spec Ready" "$status"
run_test "legacy_field_value_type_alias_read" "Workflow" "$tracker_type"
run_test "legacy_field_value_avoids_full_board_scan" "" "$(forbidden_project_reads)"

reset_log
export MOCK_PROJECT_ITEM_MODE=missing_fields
missing_fields_stderr="$(workflow_github_project_item_for_issue 824 1 2>&1 >/dev/null || true)"
unset MOCK_PROJECT_ITEM_MODE
case "$missing_fields_stderr" in
  *"named exactly 'Status'"*"named exactly 'Type'"*) missing_fields_result="warned" ;;
  *) missing_fields_result="$missing_fields_stderr" ;;
esac
run_test "project_item_missing_named_fields_warns" "warned" "$missing_fields_result"

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
export MOCK_PROJECT_ITEM_MODE=released
update_output="$(update_tracker_status_best_effort 824 "Merged")"
case "$update_output" in
  *"already at status 'Released' (more advanced than 'Merged'); skipping rollback"*) update_result="rollback-skipped" ;;
  *) update_result="$update_output" ;;
esac
run_test "status_update_blocks_backward_move_by_default" "rollback-skipped" "$update_result"
run_test "status_update_default_backward_no_mutation" "0" "$(count_log_matches 'updateProjectV2ItemFieldValue')"

reset_log
update_output="$(update_tracker_status_best_effort 824 "Merged" "" "allow-backward")"
unset MOCK_PROJECT_ITEM_MODE
case "$update_output" in
  *"Updating tracker status for issue #824 to 'Merged'"*) update_result="updated" ;;
  *) update_result="$update_output" ;;
esac
run_test "status_update_allows_explicit_backward_move" "updated" "$update_result"
run_test "status_update_explicit_backward_mutates_project_item" "1" "$(count_log_matches 'updateProjectV2ItemFieldValue')"

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
__workflow_project_type_field_cache_preferred=""
__workflow_project_type_field_cache_json=""
export MOCK_STATUS_FIELD_MODE=paginated
type_field_json="$(workflow_github_project_type_field_json "PVT_project_1")"
unset MOCK_STATUS_FIELD_MODE
type_field_id="$(printf '%s' "$type_field_json" | jq -r '.field_id // empty')"
run_test "type_field_lookup_paginates" "PVTSSF_type" "$type_field_id"
run_test "type_field_lookup_uses_two_field_queries" "2" "$(count_log_matches 'fields')"

reset_log
__workflow_project_type_field_cache_project_id=""
__workflow_project_type_field_cache_preferred=""
__workflow_project_type_field_cache_json=""
export MOCK_STATUS_FIELD_MODE=custom_type_after_type
type_field_json="$(workflow_github_project_type_field_json "PVT_project_1")"
unset MOCK_STATUS_FIELD_MODE
type_field_id="$(printf '%s' "$type_field_json" | jq -r '.field_id // empty')"
type_field_name="$(printf '%s' "$type_field_json" | jq -r '.field_name // empty')"
run_test "type_field_prefers_custom_type_after_type" "PVTSSF_custom_type" "$type_field_id"
run_test "type_field_reports_custom_type_name" "Custom Type" "$type_field_name"
run_test "type_field_custom_type_after_type_uses_two_field_queries" "2" "$(count_log_matches 'fields')"

reset_log
__workflow_project_type_field_cache_project_id=""
__workflow_project_type_field_cache_preferred=""
__workflow_project_type_field_cache_json=""
workflow_issue_tracker_custom_field() {
  case "$1" in
    type_field) printf 'Configured Type\n' ;;
    *) printf '\n' ;;
  esac
}
export MOCK_STATUS_FIELD_MODE=configured_type
type_field_json="$(workflow_github_project_type_field_json "PVT_project_1")"
unset MOCK_STATUS_FIELD_MODE
type_field_id="$(printf '%s' "$type_field_json" | jq -r '.field_id // empty')"
run_test "type_field_prefers_configured_name" "PVTSSF_configured_type" "$type_field_id"

# Restore the real custom-field helper after the override above.
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"
workflow_issue_tracker_provider_raw() {
  printf '%s\n' "${MOCK_TRACKER_PROVIDER:-github_projects}"
}
workflow_issue_tracker_project_number() {
  printf '%s\n' "${MOCK_TRACKER_PROJECT_NUMBER-1}"
}

reset_log
type_field_output=""
type_field_exit=0
type_field_output="$(workflow_github_project_type_field_json "" 2>/dev/null)" || type_field_exit=$?
run_test "type_field_empty_project_id_returns_nonzero" "1" "$type_field_exit"
run_test "type_field_empty_project_id_empty_output" "" "$type_field_output"
run_test "type_field_empty_project_id_avoids_graphql" "0" "$(count_log_matches 'api graphql')"

reset_log
__workflow_project_type_field_cache_project_id=""
__workflow_project_type_field_cache_preferred=""
__workflow_project_type_field_cache_json=""
type_field_json="$(workflow_github_project_type_field_json "PVT_project_1")"
type_field_id_one="$(printf '%s' "$type_field_json" | jq -r '.field_id // empty')"
type_field_json="$(workflow_github_project_type_field_json "PVT_project_2")"
type_field_id_two="$(printf '%s' "$type_field_json" | jq -r '.field_id // empty')"
run_test "type_field_cache_project_one_id" "PVTSSF_type" "$type_field_id_one"
run_test "type_field_cache_project_two_id" "PVTSSF_type_project_2" "$type_field_id_two"
run_test "type_field_cache_scoped_by_project" "2" "$(count_log_matches 'fields')"

reset_log
__workflow_project_type_field_cache_project_id=""
__workflow_project_type_field_cache_preferred=""
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
__workflow_project_type_field_cache_preferred=""
__workflow_project_type_field_cache_json=""
export MOCK_STATUS_FIELD_MODE=graphql_fail
type_field_stderr=""
type_field_stderr="$(workflow_github_project_type_field_json "PVT_project_1" 2>&1 >/dev/null)" || true
unset MOCK_STATUS_FIELD_MODE
case "$type_field_stderr" in
  *"GraphQL project Type field lookup failed"*"  gh: GraphQL failure"*) type_field_stderr_result="captured" ;;
  *) type_field_stderr_result="$type_field_stderr" ;;
esac
run_test "type_field_graphql_failure_reports_captured_gh_stderr" "captured" "$type_field_stderr_result"

reset_log
__workflow_project_status_field_cache_project_id=""
__workflow_project_status_field_cache_json=""
export MOCK_STATUS_FIELD_MODE=graphql_fail
status_field_stderr=""
status_field_stderr="$(workflow_github_project_status_field_json "PVT_project_1" 2>&1 >/dev/null)" || true
unset MOCK_STATUS_FIELD_MODE
case "$status_field_stderr" in
  *"GraphQL project Status field lookup failed"*"  gh: GraphQL failure"*) status_field_stderr_result="captured" ;;
  *) status_field_stderr_result="$status_field_stderr" ;;
esac
run_test "status_field_graphql_failure_reports_captured_gh_stderr" "captured" "$status_field_stderr_result"

reset_log
__workflow_project_type_field_cache_project_id=""
__workflow_project_type_field_cache_preferred=""
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
run_test "workflow_type_discovery_filters_terminal_statuses" "824" "$workflow_issue_numbers"
run_test "workflow_type_discovery_uses_single_board_scan" "1" "$(count_log_matches 'project item-list')"

reset_log
export MOCK_TRACKER_PROVIDER=linear
tracker_type="$(get_tracker_type_for_issue 824)"
type_update_output="$(update_tracker_type_best_effort 824 "Workflow" 2>&1)"
workflow_issues="$(list_open_workflow_type_issues)"
unset MOCK_TRACKER_PROVIDER
run_test "type_helpers_wrong_provider_empty_read" "" "$tracker_type"
case "$type_update_output" in
  *"does not support GitHub Projects Type updates"*) provider_guard_result="warned" ;;
  *) provider_guard_result="$type_update_output" ;;
esac
run_test "type_helpers_wrong_provider_warns" "warned" "$provider_guard_result"
run_test "type_helpers_wrong_provider_empty_list" "[]" "$(printf '%s' "$workflow_issues" | jq -c '.')"
run_test "type_helpers_wrong_provider_avoids_api" "0" "$(count_log_matches 'api graphql|issue list|project item-list')"

reset_log
milestone_number="$(workflow_github_milestone_number "v1.2.3")"
run_test "release_stamp_finds_existing_milestone" "7" "$milestone_number"
stamp_output="$(record_release_for_issue_best_effort 824 "v1.2.3" 2>&1)"
case "$stamp_output" in
  *"RELEASE_STAMPED issue=824 version=v1.2.3 provider=github_projects"*) stamp_result="stamped" ;;
  *) stamp_result="$stamp_output" ;;
esac
run_test "release_stamp_assigns_existing_milestone" "stamped" "$stamp_result"
run_test "release_stamp_existing_does_not_create_milestone" "0" "$(count_log_matches 'api -X POST repos/.*/milestones')"
run_test "release_stamp_assigns_issue_milestone" "1" "$(count_log_matches 'api -X PATCH repos/.*/issues/824 -F milestone=[0-9]')"

reset_log
export MOCK_MILESTONE_MODE=missing
stamp_output="$(record_release_for_issue_best_effort 824 "v1.2.3" 2>&1)"
unset MOCK_MILESTONE_MODE
case "$stamp_output" in
  *"RELEASE_STAMPED issue=824 version=v1.2.3 provider=github_projects"*) stamp_result="stamped" ;;
  *) stamp_result="$stamp_output" ;;
esac
run_test "release_stamp_creates_missing_milestone" "stamped" "$stamp_result"
run_test "release_stamp_missing_creates_once" "1" "$(count_log_matches 'api -X POST repos/.*/milestones')"

reset_log
export MOCK_ISSUE_PATCH_MODE=fail
stamp_output="$(record_release_for_issue_best_effort 824 "v1.2.3" 2>&1)"
unset MOCK_ISSUE_PATCH_MODE
case "$stamp_output" in
  *"RELEASE_STAMP_FAILED issue=824 version=v1.2.3 provider=github_projects reason=assignment_failed"*) stamp_result="failed" ;;
  *) stamp_result="$stamp_output" ;;
esac
run_test "release_stamp_assignment_failure_warns" "failed" "$stamp_result"

reset_log
export MOCK_TRACKER_PROVIDER=none
stamp_output="$(record_release_for_issue_best_effort 824 "v1.2.3")"
unset MOCK_TRACKER_PROVIDER
run_test "release_stamp_provider_none_skips" "RELEASE_STAMP_SKIPPED issue=824 version=v1.2.3 provider=none reason=provider_none" "$stamp_output"
run_test "release_stamp_provider_none_avoids_api" "0" "$(count_log_matches 'api |issue edit')"

reset_log
export MOCK_TRACKER_PROVIDER=linear
stamp_output="$(record_release_for_issue_best_effort 824 "v1.2.3")"
unset MOCK_TRACKER_PROVIDER
case "$stamp_output" in
  *"RELEASE_STAMP_SKIPPED issue=824 version=v1.2.3 provider=linear reason=mcp_required release_label=release/v1.2.3"*) stamp_result="linear-skip" ;;
  *) stamp_result="$stamp_output" ;;
esac
run_test "release_stamp_linear_requires_mcp" "linear-skip" "$stamp_result"
run_test "release_stamp_linear_avoids_api" "0" "$(count_log_matches 'api |issue edit')"

reset_log
export MOCK_TRACKER_PROVIDER=jira
stamp_output="$(record_release_for_issue_best_effort 824 "v1.2.3")"
unset MOCK_TRACKER_PROVIDER
run_test "release_stamp_unsupported_provider_skips" "RELEASE_STAMP_SKIPPED issue=824 version=v1.2.3 provider=jira reason=unsupported_provider" "$stamp_output"
run_test "release_stamp_unsupported_provider_avoids_api" "0" "$(count_log_matches 'api |issue edit')"

reset_log
finalize_output="$(finalize_release_marker_best_effort "v1.2.3" 2>&1)"
case "$finalize_output" in
  *"Release marker finalized: v1.2.3"*) finalize_result="finalized" ;;
  *) finalize_result="$finalize_output" ;;
esac
run_test "release_marker_finalize_closes_milestone" "finalized" "$finalize_result"
run_test "release_marker_finalize_calls_patch" "1" "$(count_log_matches 'api -X PATCH repos/.*/milestones/7 -f state=closed')"

reset_log
export MOCK_MILESTONE_CLOSE_MODE=fail
if finalize_output="$(finalize_release_marker_best_effort "v1.2.3" 2>&1)"; then
  finalize_failure_result="unexpected-success"
else
  case "$finalize_output" in
    *"Warning: could not close GitHub release milestone 'v1.2.3'."*) finalize_failure_result="failed" ;;
    *) finalize_failure_result="$finalize_output" ;;
  esac
fi
unset MOCK_MILESTONE_CLOSE_MODE
run_test "release_marker_finalize_close_failure_returns_nonzero" "failed" "$finalize_failure_result"
run_test "release_marker_finalize_close_failure_calls_patch" "1" "$(count_log_matches 'api -X PATCH repos/.*/milestones/7 -f state=closed')"

reset_log
old_project_number="${GITHUB_PROJECT_NUMBER:-}"
unset GITHUB_PROJECT_NUMBER
MOCK_TRACKER_PROJECT_NUMBER=""
tracker_type="$(get_tracker_type_for_issue 824)"
type_update_output="$(update_tracker_type_best_effort 824 "Workflow" 2>&1)"
workflow_issues="$(list_open_workflow_type_issues 2>/dev/null)"
MOCK_TRACKER_PROJECT_NUMBER="not-a-number"
invalid_type_update_output="$(update_tracker_type_best_effort 824 "Workflow" 2>&1)"
invalid_workflow_issues="$(list_open_workflow_type_issues 2>/dev/null)"
export GITHUB_PROJECT_NUMBER="$old_project_number"
unset MOCK_TRACKER_PROJECT_NUMBER
run_test "type_helpers_missing_project_empty_read" "" "$tracker_type"
case "$type_update_output" in
  *"GITHUB_PROJECT_NUMBER not set"*) project_guard_result="warned" ;;
  *) project_guard_result="$type_update_output" ;;
esac
run_test "type_helpers_missing_project_warns" "warned" "$project_guard_result"
run_test "type_helpers_missing_project_empty_list" "[]" "$(printf '%s' "$workflow_issues" | jq -c '.')"
case "$invalid_type_update_output" in
  *"project number 'not-a-number' is not numeric"*) invalid_project_guard_result="warned" ;;
  *) invalid_project_guard_result="$invalid_type_update_output" ;;
esac
run_test "type_helpers_invalid_project_warns" "warned" "$invalid_project_guard_result"
run_test "type_helpers_invalid_project_empty_list" "[]" "$(printf '%s' "$invalid_workflow_issues" | jq -c '.')"
run_test "type_helpers_missing_invalid_project_avoids_api" "0" "$(count_log_matches 'api graphql|issue list|project item-list')"

resolve_owner_from_remote() {
  local remote_url="$1"
  local tmp_repo owner
  tmp_repo="$(mktemp -d)"
  (
    export MOCK_REPO_VIEW_MODE=fail
    cd "$tmp_repo"
    git init -q
    git remote add origin "$remote_url"
    owner="$(workflow_resolve_github_repo_owner 2>/dev/null)"
    printf '%s' "$owner"
  )
  rm -rf "$tmp_repo"
}

resolve_repo_from_remote() {
  local remote_url="$1"
  local tmp_repo repo_name
  tmp_repo="$(mktemp -d)"
  (
    export MOCK_REPO_VIEW_MODE=fail
    cd "$tmp_repo"
    git init -q
    git remote add origin "$remote_url"
    repo_name="$(workflow_resolve_github_repo_name 2>/dev/null)"
    printf '%s' "$repo_name"
  )
  rm -rf "$tmp_repo"
}

reset_log
run_test "remote_owner_https_fallback_validates_github_host" "lhpaul" "$(resolve_owner_from_remote "https://github.com/lhpaul/ai-dev-framework-template.git")"
run_test "remote_repo_https_fallback_validates_github_host" "ai-dev-framework-template" "$(resolve_repo_from_remote "https://github.com/lhpaul/ai-dev-framework-template.git")"
run_test "remote_owner_fallback_rejects_non_github_host" "" "$(resolve_owner_from_remote "https://github.com.evil/lhpaul/ai-dev-framework-template.git")"
run_test "remote_repo_fallback_rejects_extra_path_segments" "" "$(resolve_repo_from_remote "https://github.com/lhpaul/ai-dev-framework-template/extra.git")"
run_test "remote_owner_fallback_rejects_invalid_owner" "" "$(resolve_owner_from_remote "git@github.com:bad_owner/ai-dev-framework-template.git")"
run_test "remote_repo_fallback_rejects_invalid_repo" "" "$(resolve_repo_from_remote "git@github.com:lhpaul/bad!repo.git")"

echo ""
echo "=== workflow_github_project_named_field_json ==="

reset_log
__workflow_project_named_field_cache_keys=()
__workflow_project_named_field_cache_vals=()
named_field_tmpout="$(mktemp)"
workflow_github_project_named_field_json "PVT_project_1" "Status" > "$named_field_tmpout" 2>/dev/null
named_field_id="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('field_id',''))" < "$named_field_tmpout" 2>/dev/null)"
run_test "named_field_lookup_returns_field_id" "PVTSSF_status" "$named_field_id"
run_test "named_field_lookup_avoids_full_board_scan" "" "$(forbidden_project_reads)"

reset_log
workflow_github_project_named_field_json "PVT_project_1" "Status" > "$named_field_tmpout" 2>/dev/null
cached_field_id="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('field_id',''))" < "$named_field_tmpout" 2>/dev/null)"
rm -f "$named_field_tmpout"
run_test "named_field_cache_hit_returns_correct_id" "PVTSSF_status" "$cached_field_id"
run_test "named_field_cache_hit_makes_zero_graphql_calls" "0" "$(count_log_matches 'api graphql')"

reset_log
__workflow_project_named_field_cache_keys=()
__workflow_project_named_field_cache_vals=()
named_not_found_exit=0
named_not_found_stderr=""
named_not_found_stderr="$(workflow_github_project_named_field_json "PVT_project_1" "Priority" 2>&1 >/dev/null)" || named_not_found_exit=$?
run_test "named_field_not_found_returns_nonzero" "1" "$named_not_found_exit"
case "$named_not_found_stderr" in
  *"Priority"*"not found"*) named_not_found_result="warned" ;;
  *) named_not_found_result="$named_not_found_stderr" ;;
esac
run_test "named_field_not_found_warns" "warned" "$named_not_found_result"

reset_log
__workflow_project_named_field_cache_keys=()
__workflow_project_named_field_cache_vals=()
empty_name_exit=0
workflow_github_project_named_field_json "PVT_project_1" "" > /dev/null 2>&1 || empty_name_exit=$?
run_test "named_field_empty_name_returns_nonzero" "1" "$empty_name_exit"
run_test "named_field_empty_name_avoids_graphql" "0" "$(count_log_matches 'api graphql')"

reset_log
__workflow_project_named_field_cache_keys=()
__workflow_project_named_field_cache_vals=()
export MOCK_STATUS_FIELD_MODE=graphql_fail
named_gql_fail_exit=0
named_gql_fail_out="$(workflow_github_project_named_field_json "PVT_project_1" "Status" 2>/dev/null)" || named_gql_fail_exit=$?
unset MOCK_STATUS_FIELD_MODE
run_test "named_field_graphql_failure_returns_nonzero" "1" "$named_gql_fail_exit"
run_test "named_field_graphql_failure_empty_output" "" "$named_gql_fail_out"

reset_log
__workflow_project_named_field_cache_keys=()
__workflow_project_named_field_cache_vals=()
export MOCK_STATUS_FIELD_MODE=paginated
named_paged_json="$(workflow_github_project_named_field_json "PVT_project_1" "Priority" 2>/dev/null)"
named_paged_id="$(printf '%s' "$named_paged_json" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('field_id',''))" 2>/dev/null)"
calls_page_one="$(count_log_matches 'api graphql')"
reset_log
named_paged_status_json="$(workflow_github_project_named_field_json "PVT_project_1" "Status" 2>/dev/null)"
named_paged_status_id="$(printf '%s' "$named_paged_status_json" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('field_id',''))" 2>/dev/null)"
calls_page_two="$(count_log_matches 'api graphql')"
unset MOCK_STATUS_FIELD_MODE
run_test "named_field_found_on_first_page" "PVTSSF_other" "$named_paged_id"
run_test "named_field_first_page_uses_one_call" "1" "$calls_page_one"
run_test "named_field_found_on_second_page" "PVTSSF_status" "$named_paged_status_id"
run_test "named_field_second_page_uses_two_calls" "2" "$calls_page_two"

echo ""
echo "=== update_tracker_named_field_best_effort ==="

reset_log
__workflow_project_named_field_cache_keys=()
__workflow_project_named_field_cache_vals=()
named_update_output="$(update_tracker_named_field_best_effort 824 "Status" "Spec Ready" 2>&1)"
case "$named_update_output" in
  *"Updating tracker 'Status' for issue #824 to 'Spec Ready'"*) named_update_result="updated" ;;
  *) named_update_result="$named_update_output" ;;
esac
run_test "named_field_update_happy_path" "updated" "$named_update_result"
run_test "named_field_update_mutates_project_item" "1" "$(count_log_matches 'updateProjectV2ItemFieldValue')"
run_test "named_field_update_avoids_full_board_scan" "" "$(forbidden_project_reads)"

reset_log
__workflow_project_named_field_cache_keys=()
__workflow_project_named_field_cache_vals=()
named_miss_output="$(update_tracker_named_field_best_effort 824 "Priority" "High" 2>&1)"
case "$named_miss_output" in
  *"could not read project 'Priority' field metadata"*) named_miss_result="field-not-found" ;;
  *) named_miss_result="$named_miss_output" ;;
esac
run_test "named_field_update_field_not_found_warns" "field-not-found" "$named_miss_result"
run_test "named_field_update_field_not_found_no_mutation" "0" "$(count_log_matches 'updateProjectV2ItemFieldValue')"

reset_log
__workflow_project_named_field_cache_keys=()
__workflow_project_named_field_cache_vals=()
named_opt_output="$(update_tracker_named_field_best_effort 824 "Status" "NonExistentOption" 2>&1)"
case "$named_opt_output" in
  *"could not resolve 'Status' field or option 'NonExistentOption'"*) named_opt_result="option-not-found" ;;
  *) named_opt_result="$named_opt_output" ;;
esac
run_test "named_field_update_option_not_found_warns" "option-not-found" "$named_opt_result"
run_test "named_field_update_option_not_found_no_mutation" "0" "$(count_log_matches 'updateProjectV2ItemFieldValue')"

reset_log
export MOCK_TRACKER_PROVIDER=linear
named_linear_output="$(update_tracker_named_field_best_effort 824 "Priority" "High" 2>&1)"
unset MOCK_TRACKER_PROVIDER
case "$named_linear_output" in
  *"does not support GitHub Projects"*) named_linear_result="warned" ;;
  *) named_linear_result="$named_linear_output" ;;
esac
run_test "named_field_update_wrong_provider_warns" "warned" "$named_linear_result"
run_test "named_field_update_wrong_provider_no_mutation" "0" "$(count_log_matches 'updateProjectV2ItemFieldValue')"

reset_log
__workflow_project_named_field_cache_keys=()
__workflow_project_named_field_cache_vals=()
priority_output="$(update_tracker_priority_best_effort 824 "High" 2>&1)"
case "$priority_output" in
  *"could not read project 'Priority' field metadata"*) priority_result="routed-to-priority" ;;
  *) priority_result="$priority_output" ;;
esac
run_test "priority_convenience_routes_to_named_field" "routed-to-priority" "$priority_result"

reset_log
__workflow_project_named_field_cache_keys=()
__workflow_project_named_field_cache_vals=()
size_output="$(update_tracker_size_best_effort 824 "S" 2>&1)"
case "$size_output" in
  *"could not read project 'Size' field metadata"*) size_result="routed-to-size" ;;
  *) size_result="$size_output" ;;
esac
run_test "size_convenience_routes_to_named_field" "routed-to-size" "$size_result"

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
echo "=== Linear deferred-action signal tests (#966) ==="

# Restore workflow_github_project_item_for_issue to the real implementation
# (a prior test overwrote it with a broken stub to test parse-failure handling).
# Re-source workflow-lib.sh so the real function definition is available again.
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"
workflow_issue_tracker_provider_raw() {
  printf '%s\n' "${MOCK_TRACKER_PROVIDER:-github_projects}"
}
workflow_issue_tracker_project_number() {
  printf '%s\n' "${MOCK_TRACKER_PROJECT_NUMBER-1}"
}

# Test: emit_linear_deferred_action formats the canonical line.
# Multi-word values are single-quoted to make the format unambiguous for parsers
# (e.g. target_status='Plan in Review' rather than target_status=Plan in Review).
emit_result="$(emit_linear_deferred_action "set_status" "ENG-123" "target_status=Plan in Review")"
run_test "emit_linear_deferred_action_set_status" \
  "TRACKER_ACTION_REQUIRED=set_status issue=ENG-123 target_status='Plan in Review'" \
  "$emit_result"

emit_read_result="$(emit_linear_deferred_action "read_status" "ENG-456")"
run_test "emit_linear_deferred_action_read_status" \
  "TRACKER_ACTION_REQUIRED=read_status issue=ENG-456" \
  "$emit_read_result"

# Single-word values are not quoted (no ambiguity).
emit_single_word_result="$(emit_linear_deferred_action "set_status" "ENG-000" "target_status=Backlog")"
run_test "emit_linear_deferred_action_single_word_unquoted" \
  "TRACKER_ACTION_REQUIRED=set_status issue=ENG-000 target_status=Backlog" \
  "$emit_single_word_result"

# Note: create_item is NOT emitted via emit_linear_deferred_action.
# add-backlog-item.sh uses printf directly with "title=<title>" (not "issue=<id>")
# because there is no issue ID for a new item being created.
# That path is covered in test-add-backlog-item.sh (linear_create_item_* tests).

# Test: workflow_emit_deferred_tracker_action is a public alias
alias_result="$(workflow_emit_deferred_tracker_action "set_status" "ENG-789" "target_status=Backlog")"
run_test "workflow_emit_deferred_tracker_action_alias" \
  "TRACKER_ACTION_REQUIRED=set_status issue=ENG-789 target_status=Backlog" \
  "$alias_result"

# Test: update_tracker_status_best_effort for Linear emits TRACKER_ACTION_REQUIRED=set_status
reset_log
export MOCK_TRACKER_PROVIDER=linear
linear_update_out="$(update_tracker_status_best_effort ENG-123 "Plan in Review" 2>/dev/null)"
unset MOCK_TRACKER_PROVIDER
case "$linear_update_out" in
  *"TRACKER_ACTION_REQUIRED=set_status"*) linear_update_result="deferred" ;;
  *) linear_update_result="$linear_update_out" ;;
esac
run_test "linear_update_emits_deferred_action" "deferred" "$linear_update_result"

# Multi-word status value must be single-quoted in the output.
case "$linear_update_out" in
  *"target_status='Plan in Review'"*) linear_update_target_result="has-target" ;;
  *) linear_update_target_result="missing-target" ;;
esac
run_test "linear_update_deferred_action_has_target_status" "has-target" "$linear_update_target_result"

# Confirm no unstructured Warning: line from old behavior
case "$linear_update_out" in
  *"Warning: Linear tracker detected"*) linear_update_warn_result="has-warning" ;;
  *) linear_update_warn_result="no-warning" ;;
esac
run_test "linear_update_no_unstructured_warning" "no-warning" "$linear_update_warn_result"

# Confirm no GitHub mutation was attempted
run_test "linear_update_no_mutation" "0" "$(count_log_matches 'updateProjectV2ItemFieldValue')"

# Test: get_tracker_status_for_issue for Linear emits TRACKER_ACTION_REQUIRED=read_status
reset_log
export MOCK_TRACKER_PROVIDER=linear
linear_status_out="$(get_tracker_status_for_issue ENG-123 2>/dev/null)"
unset MOCK_TRACKER_PROVIDER
case "$linear_status_out" in
  *"TRACKER_ACTION_REQUIRED=read_status"*) linear_status_result="deferred" ;;
  *) linear_status_result="$linear_status_out" ;;
esac
run_test "linear_get_status_emits_deferred_action" "deferred" "$linear_status_result"

# Confirm no GitHub query was attempted
run_test "linear_get_status_no_gh_query" "0" "$(count_log_matches 'api graphql')"

# Test: GitHub provider status read is unaffected (regression guard)
reset_log
gh_status="$(get_tracker_status_for_issue 824 2>/dev/null)"
run_test "github_get_status_unchanged" "Spec Ready" "$gh_status"

# Test: GitHub provider update is unaffected (backward-guard regression)
reset_log
export MOCK_PROJECT_ITEM_MODE=released
gh_backward_out="$(update_tracker_status_best_effort 824 "Merged" 2>&1)"
unset MOCK_PROJECT_ITEM_MODE
case "$gh_backward_out" in
  *"skipping rollback"*) gh_backward_result="rollback-skipped" ;;
  *) gh_backward_result="$gh_backward_out" ;;
esac
run_test "github_update_backward_guard_unchanged" "rollback-skipped" "$gh_backward_result"

echo ""
echo "Test summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
