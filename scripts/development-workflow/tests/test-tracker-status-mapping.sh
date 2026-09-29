#!/usr/bin/env bash
# test-tracker-status-mapping.sh — canonical tracker Status mapping (issue #1564).
#
# Verifies:
#   1. docs/workflow/development-workflow/tracker-status-mapping.md and
#      workflow_tracker_status_for_event agree cell for cell (AC-2: the mapping
#      is defined once — the page cannot silently drift from the code).
#   2. The documented vocabulary matches workflow_canonical_tracker_statuses
#      and workflow_status_order.
#   3. Branch-to-stage resolution and unknown event/stage/branch refusals.
#   4. tracker-status-for.sh resolves deterministically (AC-3) and, with
#      --apply, names the board's valid options and exits 3 on an unknown
#      option (AC-1) while applying a known one.
#
# Usage: bash scripts/development-workflow/tests/test-tracker-status-mapping.sh
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/tracker-status-for.sh
# covers: docs/workflow/development-workflow/tracker-status-mapping.md

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
DOC="$REPO_ROOT/docs/workflow/development-workflow/tracker-status-mapping.md"
CLI="$REPO_ROOT/scripts/development-workflow/tracker-status-for.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name — expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# --- 1. Document table <-> function, cell for cell ---------------------------
# Rows look like: | `event` | Spec cell | Plan cell | Implementation cell |
table_rows="$(awk -F'|' '
  /^\| `[a-z-]+` \|/ {
    event = $2; gsub(/[ `]/, "", event)
    for (i = 3; i <= 5; i++) { cell = $i; sub(/^ +/, "", cell); sub(/ +$/, "", cell); cells[i] = cell }
    print event "\t" cells[3] "\t" cells[4] "\t" cells[5]
  }' "$DOC")"
row_count="$(printf '%s\n' "$table_rows" | grep -c . || true)"
run_test "doc_table_has_eight_event_rows" "8" "$row_count"

stages=(spec plan implementation)
doc_mismatches=""
while IFS=$'\t' read -r event spec_cell plan_cell impl_cell; do
  [ -n "$event" ] || continue
  cells=("$spec_cell" "$plan_cell" "$impl_cell")
  for idx in 0 1 2; do
    stage="${stages[$idx]}"
    cell="${cells[$idx]}"
    rc=0
    actual="$(workflow_tracker_status_for_event "$event" "$stage" 2>/dev/null)" || rc=$?
    case "$cell" in
      "no change") expected_rc=0; expected="" ;;
      "—") expected_rc=2; expected="" ;;
      *) expected_rc=0; expected="$cell" ;;
    esac
    if [ "$rc" -ne "$expected_rc" ] || [ "$actual" != "$expected" ]; then
      doc_mismatches="${doc_mismatches}${event}/${stage}: doc='${cell}' fn='${actual}' rc=${rc}; "
    fi
  done
done <<< "$table_rows"
run_test "doc_table_matches_function" "" "$doc_mismatches"

# --- 2. Vocabulary -----------------------------------------------------------
doc_vocab="$(awk '/^## Canonical Status Vocabulary/{f=1; next} /^## /{f=0} f && /^[0-9]+\. `/{ s=$0; sub(/^[0-9]+\. `/, "", s); sub(/`.*$/, "", s); print s }' "$DOC" | paste -sd'|' -)"
fn_vocab="$(workflow_canonical_tracker_statuses | grep -vx 'Cancelled' | paste -sd'|' -)"
run_test "doc_vocabulary_matches_function" "$fn_vocab" "$doc_vocab"
run_test "vocabulary_ends_with_cancelled" "Cancelled" "$(workflow_canonical_tracker_statuses | tail -1)"

order_errors=""
position=0
while IFS= read -r status; do
  [ "$status" = "Cancelled" ] && continue
  if [ "$(workflow_status_order "$status")" != "$position" ]; then
    order_errors="${order_errors}${status}; "
  fi
  position=$((position + 1))
done < <(workflow_canonical_tracker_statuses)
run_test "vocabulary_matches_status_order" "" "$order_errors"

# Every status the mapping can emit is in the vocabulary.
unknown_emitted=""
for event in dispatch ready-for-human-review merged released; do
  for stage in "${stages[@]}"; do
    status="$(workflow_tracker_status_for_event "$event" "$stage" 2>/dev/null)" || continue
    [ -n "$status" ] || continue
    workflow_canonical_tracker_statuses | grep -qxF "$status" || unknown_emitted="${unknown_emitted}${status}; "
  done
done
run_test "mapping_emits_only_canonical_statuses" "" "$unknown_emitted"

# --- 3. Branch -> stage and refusals -----------------------------------------
run_test "stage_spec_branch" "spec" "$(workflow_tracker_stage_for_branch spec/12-x)"
run_test "stage_plan_branch" "plan" "$(workflow_tracker_stage_for_branch implementation-plan/12-x)"
for prefix in feature fix refactor hotfix; do
  run_test "stage_${prefix}_branch" "implementation" "$(workflow_tracker_stage_for_branch "${prefix}/12-x")"
done
for branch in release/v1.2.3 backport/hotfix/12-x develop-epic develop spec/ ""; do
  rc=0
  workflow_tracker_stage_for_branch "$branch" >/dev/null 2>&1 || rc=$?
  run_test "stage_refused_for_'${branch}'" "1" "$rc"
done

rc=0; err="$(workflow_tracker_status_for_event "In Progress" implementation 2>&1)" || rc=$?
run_test "unknown_event_exit_two" "2" "$rc"
case "$err" in *"Valid events: dispatch, ready-for-human-review, merged, released"*) r="named" ;; *) r="$err" ;; esac
run_test "unknown_event_names_valid_events" "named" "$r"
rc=0; err="$(workflow_tracker_status_for_event merged review 2>&1)" || rc=$?
run_test "unknown_stage_exit_two" "2" "$rc"
case "$err" in *"Valid stages: spec, plan, implementation"*) r="named" ;; *) r="$err" ;; esac
run_test "unknown_stage_names_valid_stages" "named" "$r"
rc=0; workflow_tracker_status_for_event released plan >/dev/null 2>&1 || rc=$?
run_test "released_refused_for_plan" "2" "$rc"

# --- 4. CLI --------------------------------------------------------------------
cli_out="$(bash "$CLI" --event ready-for-human-review --branch fix/1564-x)"
run_test "cli_resolves_ready_for_fix" "Development in Review" "$(printf '%s\n' "$cli_out" | sed -n 's/^TRACKER_STATUS=//p')"
run_test "cli_reports_set_action" "set" "$(printf '%s\n' "$cli_out" | sed -n 's/^TRACKER_STATUS_ACTION=//p')"
cli_again="$(bash "$CLI" --event ready-for-human-review --branch fix/1564-x)"
run_test "cli_is_deterministic" "$cli_out" "$cli_again"
run_test "cli_branch_and_stage_agree" "$cli_out" "$(bash "$CLI" --event ready-for-human-review --stage implementation)"

none_out="$(bash "$CLI" --event needs-fixes --branch spec/7-x)"
run_test "cli_needs_fixes_no_change" "none" "$(printf '%s\n' "$none_out" | sed -n 's/^TRACKER_STATUS_ACTION=//p')"
run_test "cli_list_matches_vocabulary" "$(workflow_canonical_tracker_statuses)" "$(bash "$CLI" --list)"

for bad in "--event merged --branch release/v1.0.0" "--event bogus --stage spec" "--event merged" \
           "--event merged --stage spec --branch spec/1-x" "--event merged --stage spec --issue 5" \
           "--event merged --stage spec --apply"; do
  rc=0
  # shellcheck disable=SC2086 # intentional word splitting of the argument list
  bash "$CLI" $bad >/dev/null 2>&1 || rc=$?
  run_test "cli_refuses_[$bad]" "2" "$rc"
done

# --apply against a mocked gh. The Status field offers only a subset of the
# canonical vocabulary, so "Development in Review" is an unknown option.
MOCK_BIN="$TMP_DIR/bin"
CALL_LOG="$TMP_DIR/gh-calls.log"
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"
cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"
case "$*" in
  "repo view --json owner --jq .owner.login") printf 'lhpaul\n' ;;
  "repo view --json name --jq .name") printf 'ai-dev-framework-template\n' ;;
  *"api graphql"*)
    case "$*" in
      *"projectV2(number:"*)
        printf '%s\n' '{"data":{"user":{"projectV2":{"id":"PVT_project_1"}},"organization":null}}'
        ;;
      *"projectItems(first:"*)
        printf '%s\n' '{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_item","project":{"id":"PVT_project_1","number":1},"status":{"name":"In Development"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}'
        ;;
      *"fields(first:"*)
        if [ "${MOCK_FIELDS_MODE:-ok}" = "fail" ]; then
          printf 'GraphQL failure\n' >&2
          exit 42
        fi
        printf '%s\n' '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status","options":[{"id":"OPT_plan_ready","name":"Plan Ready"},{"id":"OPT_dev","name":"In Development"},{"id":"OPT_merged","name":"Merged"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}'
        ;;
      *"updateProjectV2ItemFieldValue"*)
        if [ "${MOCK_MUTATION_MODE:-ok}" = "fail" ]; then
          printf 'mutation failure\n' >&2
          exit 42
        fi
        printf '%s\n' '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"PVTI_item"}}}}'
        ;;
      *) printf '{}\n' ;;
    esac
    ;;
  *) printf 'unexpected gh invocation: gh %s\n' "$*" >&2; exit 64 ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"

CONFIG="$TMP_DIR/ai-dev-workflow.yaml"
cat > "$CONFIG" <<'YAML'
schema_version: 2
issue_tracker:
  provider: github_projects
  project_number: 1
YAML

run_cli_mocked() {
  PATH="$MOCK_BIN:$PATH" MOCK_GH_CALL_LOG="$CALL_LOG" AI_DEV_WORKFLOW_CONFIG_FILE="$CONFIG" \
    GITHUB_PROJECT_OWNER=lhpaul GITHUB_PROJECT_NUMBER=1 bash "$CLI" "$@"
}
mutations() { grep -c 'updateProjectV2ItemFieldValue' "$CALL_LOG" || true; }

: > "$CALL_LOG"
rc=0; apply_out="$(run_cli_mocked --event ready-for-human-review --branch fix/9-x --apply --issue 9 2>&1)" || rc=$?
run_test "apply_unknown_option_exit_three" "3" "$rc"
run_test "apply_unknown_option_result" "unresolved" "$(printf '%s\n' "$apply_out" | sed -n 's/^TRACKER_STATUS_RESULT=//p')"
case "$apply_out" in *"Valid options: Plan Ready, In Development, Merged."*) r="named" ;; *) r="$apply_out" ;; esac
run_test "apply_unknown_option_names_valid_options" "named" "$r"
run_test "apply_unknown_option_does_not_mutate" "0" "$(mutations)"

: > "$CALL_LOG"
rc=0; apply_out="$(run_cli_mocked --event merged --branch fix/9-x --apply --issue 9 2>&1)" || rc=$?
run_test "apply_known_option_exit_zero" "0" "$rc"
run_test "apply_known_option_result" "applied" "$(printf '%s\n' "$apply_out" | sed -n 's/^TRACKER_STATUS_RESULT=//p')"
run_test "apply_known_option_mutates_once" "1" "$(mutations)"

: > "$CALL_LOG"
rc=0; apply_out="$(run_cli_mocked --event needs-fixes --branch fix/9-x --apply --issue 9 2>&1)" || rc=$?
run_test "apply_no_change_exit_zero" "0" "$rc"
run_test "apply_no_change_result" "none" "$(printf '%s\n' "$apply_out" | sed -n 's/^TRACKER_STATUS_RESULT=//p')"
run_test "apply_no_change_makes_no_gh_call" "0" "$(grep -c . "$CALL_LOG" || true)"

# A transient failure is reported as "failed" (exit 0, best-effort), never
# folded into "skipped", so the runner can record it.
: > "$CALL_LOG"
rc=0; apply_out="$(MOCK_FIELDS_MODE=fail run_cli_mocked --event merged --branch fix/9-x --apply --issue 9 2>&1)" || rc=$?
run_test "apply_field_unavailable_exit_zero" "0" "$rc"
run_test "apply_field_unavailable_result_failed" "failed" "$(printf '%s\n' "$apply_out" | sed -n 's/^TRACKER_STATUS_RESULT=//p')"
run_test "apply_field_unavailable_does_not_mutate" "0" "$(mutations)"

: > "$CALL_LOG"
rc=0; apply_out="$(MOCK_MUTATION_MODE=fail run_cli_mocked --event merged --branch fix/9-x --apply --issue 9 2>&1)" || rc=$?
run_test "apply_mutation_failure_exit_zero" "0" "$rc"
run_test "apply_mutation_failure_result_failed" "failed" "$(printf '%s\n' "$apply_out" | sed -n 's/^TRACKER_STATUS_RESULT=//p')"
case "$apply_out" in *"TRACKER_STATUS_UPDATE_FAILED issue=9 requested='Merged' reason=mutation_failed"*) r="marker" ;; *) r="$apply_out" ;; esac
run_test "apply_mutation_failure_emits_marker" "marker" "$r"

# Already further along: the helper's forward-only guard skips the write.
: > "$CALL_LOG"
rc=0; apply_out="$(run_cli_mocked --event merged --branch implementation-plan/9-x --apply --issue 9 2>&1)" || rc=$?
run_test "apply_rollback_guard_exit_zero" "0" "$rc"
run_test "apply_rollback_guard_result_skipped" "skipped" "$(printf '%s\n' "$apply_out" | sed -n 's/^TRACKER_STATUS_RESULT=//p')"
run_test "apply_rollback_guard_does_not_mutate" "0" "$(mutations)"

echo ""
echo "Test summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
