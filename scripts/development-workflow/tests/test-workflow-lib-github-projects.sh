#!/usr/bin/env bash
# test-workflow-lib-github-projects.sh — Unit tests for GitHub Projects helpers.
#
# Exercises issue #824's rate-limit fix:
#   1. get_tracker_status_for_issue uses targeted issue->projectItems GraphQL
#   2. ensure_on_project_board checks membership without full-board pagination
#   3. update_tracker_status_best_effort resolves item/status IDs without item-list
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
{"data":{"repository":{"issue":{"projectItems":{"nodes":[]}}}}}
JSON
        else
          cat <<'JSON'
{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_item_824","project":{"id":"PVT_project_1","number":1},"fieldValueByName":{"name":"Spec Ready"}}]}}}}}
JSON
        fi
        ;;
      *"fields(first:"*)
        cat <<'JSON'
{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status","options":[{"id":"OPT_spec_ready","name":"Spec Ready"},{"id":"OPT_in_development","name":"In Development"}]}]}}}}
JSON
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

echo ""
echo "Test summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
