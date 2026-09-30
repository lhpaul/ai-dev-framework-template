#!/usr/bin/env bash
# test-status-check-rollup-dedupe.sh - the one statusCheckRollup dedupe (#1559).
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/pr-ci-loop.sh scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/item-completion-self-check.sh scripts/development-workflow/batch-merge.sh
# covers: scripts/development-workflow/discover-workflow-state.sh scripts/development-workflow/apply-readiness-labels.sh
# covers: scripts/development-workflow/run-epic-risk-classifier.sh scripts/development-workflow/run-epic-delegated-gate.sh
# covers: scripts/development-workflow/haystack-reviewer.sh
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
#
# A consumer added later is caught by the Part 2 scan on the next run that
# selects this suite (any workflow-lib.sh change, or the scheduled full run).
#
# GitHub's statusCheckRollup keeps superseded runs: PR #1547 carried
# `policy failure 05:26:31` and `policy success 05:28:16` for one SHA. A scan
# over the raw rollup reports a failure that is no longer true.
#
#   Part 1 — the shared jq definition (AC-2, AC-3, and its edge rules).
#   Part 2 — the inventory: every script that reads the rollup (or REST
#            check-runs) routes it through the shared definition (AC-1), and
#            no script outside
#            workflow-lib.sh carries its own copy of the grouping (AC-4). This
#            is what keeps a NEW consumer from silently scanning the raw rollup.
#   Part 3 — discover-workflow-state.sh, the one list-view consumer, end to end.
#   Part 4 — Protocol 91 Step 8a Check 0, the readiness gate's own CI count,
#            extracted from the protocol and executed against REST check-run
#            pages (the REST endpoint keeps superseded runs as well).
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

# REST `commits/<sha>/check-runs` has the same property: its default
# filter=latest is latest per CHECK SUITE, and a re-run workflow is a new
# suite, so PR #1547's head returns both `policy` runs from that endpoint too.
# Every script reading it is a consumer, except validate-closing-keyword-scope.sh,
# which lists filter=all on purpose to find duplicates of its OWN check run.
while IFS= read -r path; do
  case " ${consumers[*]} " in
    *" $path "*) ;;
    *) consumers+=("$path") ;;
  esac
done < <(
  cd "$WF_DIR" && grep -lE 'commits/[^"]*/check-runs' -- *.sh 2>/dev/null \
    | grep -vE '^(workflow-lib|validate-closing-keyword-scope)\.sh$' | sort
)

run_test "consumer_inventory_nonempty" "yes" "$([ "${#consumers[@]}" -ge 9 ] && echo yes || echo no)"
for consumer in "${consumers[@]}"; do
  if grep -Eq 'normalize_status_check_rollup|dedupe_status_check_rollup' "$WF_DIR/$consumer"; then
    run_test "consumer_uses_shared_dedupe:${consumer}" "yes" "yes"
  else
    run_test "consumer_uses_shared_dedupe:${consumer}" "yes" "no"
  fi
done

# AC-4: the grouping lives in workflow-lib.sh only. These are the markers of
# every copy that existed before #1559 (the __check_key/__check_ts copies, the
# classifier's __run_epic_* copy, batch-merge's check_key grouping, and the
# REST statuses group_by(.context) | max_by(.updated_at) copies).
copies="$(
  cd "$WF_DIR" && grep -nE '__check_key|__check_ts|__run_epic_(name|timestamp)|group_by\(check_key\)|group_by\(\.context\)|max_by\(\.updated_at\)' -- *.sh *.py 2>/dev/null \
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

echo ""
echo "=== Part 4: Protocol 91 Step 8a Check 0 (executed from the protocol) ==="

# Check 0 is fenced bash in the protocol, not a script, so extract it and run
# it: from its heading comment up to (not including) the verdict `if`. The
# check-runs pages are the PR #1547 shape — the same `policy` check in two
# suites, failure then success.
P91="$REPO_ROOT/docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"
CHECK0="$TMP_ROOT/check0.sh"
awk '/^# Check 0: CI must be green/{p=1} /^if \[ "\$CI_FAILING" -gt 0 \]/{p=0} p' "$P91" > "$CHECK0"
run_test "check0_extracted" "yes" "$(grep -q 'latest_check_runs_for_sha' "$CHECK0" && grep -q '^CI_TOTAL=' "$CHECK0" && echo yes || echo no)"

CHECK0_BIN="$TMP_ROOT/check0-bin"
mkdir -p "$CHECK0_BIN"
cat > "$CHECK0_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  "pr view"*) printf '%s\n' 8aaf67859e8a6b2b2cc64b288b94f46019753f71 ;;
  "repo view"*) printf '%s\n' owner/repo ;;
  *"/check-runs"*) printf '%s\n' "$MOCK_CHECK_RUN_PAGES" ;;
  *"/actions/runs"*) printf '%s\n' "$MOCK_WORKFLOW_RUN_PAGES" ;;
  *"/status"*) printf '%s\n' '[{"state":"success","statuses":[{"context":"Reviewer-loop completion guard","state":"success"}]}]' ;;
  *) exit 64 ;;
esac
MOCK_GH
chmod +x "$CHECK0_BIN/gh"

# A ${VAR:-...} default containing braces does not survive parameter
# expansion, so the empty workflow-run page is a plain variable.
no_workflow_runs='[{"workflow_runs":[]}]'
run_check0() {
  local workflow_pages="${2:-$no_workflow_runs}"
  env PATH="$CHECK0_BIN:$PATH" MOCK_CHECK_RUN_PAGES="$1" MOCK_WORKFLOW_RUN_PAGES="$workflow_pages" bash -c '
    set -euo pipefail
    source "$1"
    PR_NUMBER=1547
    source "$2"
    printf "%s %s %s\n" "$CI_FAILING" "$CI_PENDING" "$CI_TOTAL"
  ' _ "$WF_DIR/workflow-lib.sh" "$CHECK0"
}

superseded_pages='[{"total_count":3,"check_runs":[
  {"name":"policy","status":"completed","conclusion":"success","started_at":"2026-08-21T05:28:16Z","check_suite":{"id":2}},
  {"name":"ShellCheck","status":"completed","conclusion":"success","started_at":"2026-08-21T05:20:00Z","check_suite":{"id":3}}]},
 {"total_count":3,"check_runs":[
  {"name":"policy","status":"completed","conclusion":"failure","started_at":"2026-08-21T05:26:31Z","check_suite":{"id":1}}]}]'
run_test "check0_superseded_failure_counts_green" "0 0 3" "$(run_check0 "$superseded_pages")"

current_failure_pages='[{"total_count":2,"check_runs":[
  {"name":"policy","status":"completed","conclusion":"failure","started_at":"2026-08-21T05:28:16Z","check_suite":{"id":2}},
  {"name":"policy","status":"completed","conclusion":"success","started_at":"2026-08-21T05:26:31Z","check_suite":{"id":1}}]}]'
run_test "check0_current_failure_still_counts" "1 0 2" "$(run_check0 "$current_failure_pages")"

# REST check runs carry no workflow name. Two workflows that both have a job
# named `test` are two checks: unit's failure must not disappear behind e2e's
# later success. Runs of ONE workflow in two suites (policy, re-triggered)
# still collapse to the latest.
two_workflow_pages='[{"total_count":4,"check_runs":[
  {"name":"test","status":"completed","conclusion":"failure","started_at":"2026-08-21T05:26:31Z","check_suite":{"id":11},"app":{"slug":"github-actions"}},
  {"name":"test","status":"completed","conclusion":"success","started_at":"2026-08-21T05:28:16Z","check_suite":{"id":12},"app":{"slug":"github-actions"}},
  {"name":"policy","status":"completed","conclusion":"failure","started_at":"2026-08-21T05:26:31Z","check_suite":{"id":13},"app":{"slug":"github-actions"}},
  {"name":"policy","status":"completed","conclusion":"success","started_at":"2026-08-21T05:28:16Z","check_suite":{"id":14},"app":{"slug":"github-actions"}}]}]'
two_workflow_runs='[{"workflow_runs":[
  {"check_suite_id":11,"name":"unit","path":".github/workflows/unit.yml"},
  {"check_suite_id":12,"name":"e2e","path":".github/workflows/e2e.yml"},
  {"check_suite_id":13,"name":"PR policy","path":".github/workflows/pr-policy.yml"},
  {"check_suite_id":14,"name":"PR policy","path":".github/workflows/pr-policy.yml"}]}]'
run_test "check0_same_job_name_other_workflow_failure_counts" "1 0 4" "$(run_check0 "$two_workflow_pages" "$two_workflow_runs")"

# Both reads fail closed.
check0_fail_bin="$TMP_ROOT/check0-fail-bin"
mkdir -p "$check0_fail_bin"
cp "$CHECK0_BIN/gh" "$check0_fail_bin/gh"
sed -i.bak 's#^  \*"/actions/runs"\*).*#  *"/actions/runs"*) exit 1 ;;#' "$check0_fail_bin/gh"
run_test "check0_fail_mock_rewritten" "1" "$(grep -c '"/actions/runs"\*) exit 1' "$check0_fail_bin/gh")"
check0_fail_out="$(env PATH="$check0_fail_bin:$PATH" MOCK_CHECK_RUN_PAGES="$superseded_pages" MOCK_WORKFLOW_RUN_PAGES="$no_workflow_runs" bash -c '
  set -euo pipefail
  source "$1"
  PR_NUMBER=1547
  source "$2"
  echo "reached-counts"
' _ "$WF_DIR/workflow-lib.sh" "$CHECK0" 2>&1; echo "status=$?")"
run_test "check0_workflow_read_failure_fails_closed" "status=5" "$(printf '%s\n' "$check0_fail_out" | tail -1)"
run_test "check0_workflow_read_failure_never_counts" "no" "$(grep -q 'reached-counts' <<<"$check0_fail_out" && echo yes || echo no)"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
