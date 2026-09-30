#!/usr/bin/env bash
# test-status-check-rollup-dedupe.sh - the one statusCheckRollup dedupe (#1559).
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/pr-ci-loop.sh scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/item-completion-self-check.sh scripts/development-workflow/batch-merge.sh
# covers: scripts/development-workflow/discover-workflow-state.sh scripts/development-workflow/apply-readiness-labels.sh
# covers: scripts/development-workflow/run-epic-risk-classifier.sh scripts/development-workflow/run-epic-delegated-gate.sh
#
# A consumer added later is caught by the Part 2 scan on the next run that
# selects this suite (any workflow-lib.sh change, or the scheduled full run).
#
# GitHub's statusCheckRollup keeps superseded runs: PR #1547 carried
# `policy failure 05:26:31` and `policy success 05:28:16` for one SHA. A scan
# over the raw rollup reports a failure that is no longer true.
#
#   Part 1 — the shared jq definition (AC-2, AC-3, and its edge rules).
#   Part 2 — the inventory: every script that reads the rollup routes it
#            through the shared definition (AC-1), and no script outside
#            workflow-lib.sh carries its own copy of the grouping (AC-4). This
#            is what keeps a NEW consumer from silently scanning the raw rollup.
#   Part 3 — discover-workflow-state.sh, the one list-view consumer, end to end.
#
# The other consumers are exercised end to end in their own suites:
# test-pr-ci-loop.sh, test-run-epic-risk-classifier.sh,
# test-run-epic-delegated-gate.sh, test-item-completion-self-check.sh,
# test-batch-merge-recheck-remaining.sh.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
WF_DIR="$REPO_ROOT/scripts/development-workflow"

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$WF_DIR/workflow-lib.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass=0
fail=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"; pass=$((pass + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"; fail=$((fail + 1))
  fi
}

# latest <rollup-array-json> — "<key>=<outcome>" per surviving entry, sorted.
latest() {
  printf '{"statusCheckRollup":%s}\n' "$1" \
    | normalize_status_check_rollup \
    | jq -r '
        map((.context // ((.workflowName // "") + "/" + (.name // "?")))
            + "=" + ([.conclusion, .state, .status] | map(select(type == "string" and . != "")) | first // "none"))
        | sort | join(",")'
}

echo "=== Part 1: shared definition ==="

# AC-2: the PR #1547 shape, listed newest-first and oldest-first.
run_test "superseded_failure_then_success_is_success" "policy=SUCCESS" "$(latest '[
  {"__typename":"StatusContext","context":"policy","state":"FAILURE","startedAt":"2026-06-01T05:26:31Z"},
  {"__typename":"StatusContext","context":"policy","state":"SUCCESS","startedAt":"2026-06-01T05:28:16Z"}]')"
run_test "superseded_failure_listed_last_is_still_success" "policy=SUCCESS" "$(latest '[
  {"__typename":"StatusContext","context":"policy","state":"SUCCESS","startedAt":"2026-06-01T05:28:16Z"},
  {"__typename":"StatusContext","context":"policy","state":"FAILURE","startedAt":"2026-06-01T05:26:31Z"}]')"
run_test "superseded_check_run_failure_is_success" "CI/lint=SUCCESS" "$(latest '[
  {"__typename":"CheckRun","name":"lint","workflowName":"CI","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-06-01T05:26:31Z"},
  {"__typename":"CheckRun","name":"lint","workflowName":"CI","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-06-01T05:28:16Z"}]')"

# AC-3: a genuine current failure survives.
run_test "current_failure_after_success_is_failure" "policy=FAILURE" "$(latest '[
  {"__typename":"StatusContext","context":"policy","state":"SUCCESS","startedAt":"2026-06-01T05:26:31Z"},
  {"__typename":"StatusContext","context":"policy","state":"FAILURE","startedAt":"2026-06-01T05:28:16Z"}]')"
run_test "single_failure_is_failure" "CI/lint=FAILURE" "$(latest '[
  {"__typename":"CheckRun","name":"lint","workflowName":"CI","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-06-01T05:26:31Z"}]')"

# A re-run that is queued has no startedAt yet (or GitHub's zero time). It is
# newer than the result it supersedes, so the check reads pending, not green.
run_test "queued_rerun_supersedes_success" "CI/lint=QUEUED" "$(latest '[
  {"__typename":"CheckRun","name":"lint","workflowName":"CI","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-06-01T05:26:31Z"},
  {"__typename":"CheckRun","name":"lint","workflowName":"CI","status":"QUEUED","conclusion":null,"startedAt":null}]')"
run_test "zero_time_rerun_supersedes_success" "CI/lint=IN_PROGRESS" "$(latest '[
  {"__typename":"CheckRun","name":"lint","workflowName":"CI","status":"IN_PROGRESS","conclusion":"","startedAt":"0001-01-01T00:00:00Z"},
  {"__typename":"CheckRun","name":"lint","workflowName":"CI","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-06-01T05:26:31Z"}]')"
run_test "pending_status_context_supersedes_success" "policy=PENDING" "$(latest '[
  {"__typename":"StatusContext","context":"policy","state":"PENDING"},
  {"__typename":"StatusContext","context":"policy","state":"SUCCESS","startedAt":"2026-06-01T05:26:31Z"}]')"

# Keys: same job name in two workflows are two checks; a status context and a
# check run of the same name are two checks; unidentifiable entries never merge.
run_test "same_name_two_workflows_stay_distinct" "e2e/test=SUCCESS,unit/test=FAILURE" "$(latest '[
  {"__typename":"CheckRun","name":"test","workflowName":"unit","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-06-01T05:26:31Z"},
  {"__typename":"CheckRun","name":"test","workflowName":"e2e","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-06-01T05:28:16Z"}]')"
run_test "unnamed_entries_are_not_merged" "2" "$(printf '%s\n' '{"statusCheckRollup":[
  {"status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-06-01T05:26:31Z"},
  {"status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-06-01T05:28:16Z"}]}' \
  | normalize_status_check_rollup | jq 'length')"

# Recency sources: REST/hand-assembled snake_case timestamps order the same
# way; with any timestamp missing, the latest input entry wins.
run_test "snake_case_timestamps_order_runs" "guard=SUCCESS" "$(printf '%s\n' '[
  {"name":"guard","status":"COMPLETED","conclusion":"SUCCESS","completed_at":"2026-06-12T10:05:00Z"},
  {"name":"guard","status":"COMPLETED","conclusion":"FAILURE","completed_at":"2026-06-12T10:00:00Z"}]' \
  | jq -r "$STATUS_CHECK_ROLLUP_DEDUPE_JQ"' dedupe_status_check_rollup | map(.name + "=" + .conclusion) | join(",")')"
run_test "missing_timestamp_uses_latest_input_entry" "guard=SUCCESS" "$(printf '%s\n' '[
  {"name":"guard","status":"COMPLETED","conclusion":"FAILURE","completed_at":"2026-06-12T10:00:00Z"},
  {"name":"guard","status":"COMPLETED","conclusion":"SUCCESS"}]' \
  | jq -r "$STATUS_CHECK_ROLLUP_DEDUPE_JQ"' dedupe_status_check_rollup | map(.name + "=" + .conclusion) | join(",")')"
run_test "equal_timestamps_use_latest_input_entry" "policy=SUCCESS" "$(latest '[
  {"context":"policy","state":"FAILURE","startedAt":"2026-06-01T05:26:31Z"},
  {"context":"policy","state":"SUCCESS","startedAt":"2026-06-01T05:26:31Z"}]')"

# Shape: helper-internal fields never leak; absent or null rollups are [].
run_test "no_internal_fields_leak" "[]" "$(printf '%s\n' '{"statusCheckRollup":[{"context":"policy","state":"SUCCESS","startedAt":"2026-06-01T05:26:31Z"}]}' \
  | normalize_status_check_rollup | jq -c '[.[] | keys[] | select(startswith("__check"))]')"
run_test "missing_rollup_is_empty" "[]" "$(printf '{}\n' | normalize_status_check_rollup | jq -c .)"
run_test "null_rollup_is_empty" "[]" "$(printf '{"statusCheckRollup":null}\n' | normalize_status_check_rollup | jq -c .)"

echo ""
echo "=== Part 2: every consumer routes through the one definition ==="

# Scripts that read statusCheckRollup (or rollup-shaped CI evidence) and act on
# it. A new consumer that is not listed here is caught by the scan below.
consumers=()
while IFS= read -r path; do
  consumers+=("$path")
done < <(
  cd "$WF_DIR" && grep -l 'statusCheckRollup' -- *.sh *.py 2>/dev/null | grep -v '^workflow-lib\.sh$' | sort
)
# The delegated gate never fetches the rollup itself, but judges rollup-shaped
# `.statusChecks` evidence copied from it (the Gate 5 case #1559 reports).
case " ${consumers[*]} " in
  *" run-epic-delegated-gate.sh "*) ;;
  *) consumers+=("run-epic-delegated-gate.sh") ;;
esac

run_test "consumer_inventory_nonempty" "yes" "$([ "${#consumers[@]}" -ge 7 ] && echo yes || echo no)"
for consumer in "${consumers[@]}"; do
  if grep -Eq 'normalize_status_check_rollup|dedupe_status_check_rollup' "$WF_DIR/$consumer"; then
    run_test "consumer_uses_shared_dedupe:${consumer}" "yes" "yes"
  else
    run_test "consumer_uses_shared_dedupe:${consumer}" "yes" "no"
  fi
done

# AC-4: the grouping lives in workflow-lib.sh only. These are the markers of
# every copy that existed before #1559 (the __check_key/__check_ts copies, the
# classifier's __run_epic_* copy, and batch-merge's check_key grouping).
copies="$(
  cd "$WF_DIR" && grep -nE '__check_key|__check_ts|__run_epic_(name|timestamp)|group_by\(check_key\)' -- *.sh *.py 2>/dev/null \
    | grep -v '^workflow-lib\.sh:' || true
)"
run_test "no_dedupe_copy_outside_workflow_lib" "" "$copies"

echo ""
echo "=== Part 3: discover-workflow-state.sh list view ==="

MOCK_BIN="$TMP_ROOT/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
# Applies --jq locally, as the real gh does, so the list consumer's program —
# including the prepended shared definition — runs for real.
jq_filter=""
prev=""
for arg in "$@"; do
  [ "$prev" = "--jq" ] && jq_filter="$arg"
  prev="$arg"
done
case "$*" in
  *"auth status"*) exit 0 ;;
  "pr list"*)
    payload='[{"number":1547,"title":"superseded","headRefName":"fix/1547-x","baseRefName":"develop","labels":[],"statusCheckRollup":[
      {"__typename":"StatusContext","context":"policy","state":"FAILURE","startedAt":"2026-06-01T05:26:31Z"},
      {"__typename":"StatusContext","context":"policy","state":"SUCCESS","startedAt":"2026-06-01T05:28:16Z"}]},
      {"number":1548,"title":"current failure","headRefName":"fix/1548-y","baseRefName":"develop","labels":[],"statusCheckRollup":[
      {"__typename":"StatusContext","context":"policy","state":"SUCCESS","startedAt":"2026-06-01T05:26:31Z"},
      {"__typename":"StatusContext","context":"policy","state":"FAILURE","startedAt":"2026-06-01T05:28:16Z"},
      {"__typename":"CheckRun","name":"lint","workflowName":"CI","status":"IN_PROGRESS","conclusion":"","startedAt":"2026-06-01T05:28:16Z"}]}]'
    if [ -n "$jq_filter" ]; then printf '%s\n' "$payload" | jq -r "$jq_filter"; else printf '%s\n' "$payload"; fi
    exit 0 ;;
  *) printf '[]\n'; exit 0 ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"

discover_out="$(cd "$REPO_ROOT" && PATH="$MOCK_BIN:$PATH" bash "$WF_DIR/discover-workflow-state.sh" 2>/dev/null || true)"
run_test "discover_superseded_failure_lists_success" "checks=SUCCESS" \
  "$(printf '%s\n' "$discover_out" | awk -F'\t' '$1 == "#1547" {print $5}')"
# Entries are listed in check-key order: check runs, then status contexts.
run_test "discover_current_failure_lists_pending_and_failure" "checks=IN_PROGRESS,FAILURE" \
  "$(printf '%s\n' "$discover_out" | awk -F'\t' '$1 == "#1548" {print $5}')"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
