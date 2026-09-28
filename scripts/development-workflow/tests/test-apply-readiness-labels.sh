#!/usr/bin/env bash
# test-apply-readiness-labels.sh - readiness-label gate tests (#1408).
# covers: scripts/development-workflow/apply-readiness-labels.sh
# covers: scripts/development-workflow/workflow-lib.sh
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
# covers: docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
#
# Readiness labels are input to the merge gates, so the gate must refuse on
# every state that does not prove a finished, clean reviewer verdict. The
# planted failing case is the absent reviewer check run: Cursor "Restrict
# Access" can make Bugbot refuse to run, and treating "no check run" as
# "reviewer clean" is the exact defect this helper exists to prevent.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/apply-readiness-labels.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass=0
fail=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    fail=$((fail + 1))
  fi
}

_BIN="$TMP_ROOT/bin"
mkdir -p "$_BIN"

cat > "$_BIN/gh" <<'GH'
#!/usr/bin/env bash
# gh stub. Payloads come from MOCK_PR_JSON / MOCK_CHECK_RUNS / MOCK_COMMENTS /
# MOCK_REVIEWS; every `pr edit` invocation is appended to MOCK_GH_LOG so a test
# can prove the label was NOT applied.
# Defaults are plain variables: a ${VAR:-{...}} default containing braces does
# not survive bash parameter expansion and silently yields invalid JSON.
labels_default='{"labels":[]}'
pr_default='{"headRefOid":"aaaa111000000000000","labels":[],"statusCheckRollup":[]}'
check_runs_default='{"check_runs":[]}'
empty_array='[]'
jq_filter=""
prev=""
for arg in "$@"; do
  [ "$prev" = "--jq" ] && jq_filter="$arg"
  prev="$arg"
done
emit() {
  if [ -n "$jq_filter" ]; then
    printf '%s\n' "$1" | jq -r "$jq_filter"
  else
    printf '%s\n' "$1"
  fi
}
case "$*" in
  *"auth status"*) exit 0 ;;
  *"pr edit"*)
    printf '%s\n' "$*" >>"${MOCK_GH_LOG:?}"
    # Record the applied label so the helper's own post-apply verification reads
    # back what this stub stored, not a canned response. MOCK_DROP_LABEL=1
    # simulates a label the API accepts and then quietly discards.
    added=""
    prev_add=""
    for arg in "$@"; do
      [ "$prev_add" = "--add-label" ] && added="$arg"
      prev_add="$arg"
    done
    if [ "${MOCK_DROP_LABEL:-0}" != "1" ] && [ -n "${MOCK_LABEL_STATE:-}" ] && [ -n "$added" ]; then
      printf '%s\n' "$added" >>"$MOCK_LABEL_STATE"
    fi
    exit "${MOCK_GH_EDIT_EXIT:-0}"
    ;;
  *"pr view"*"--json labels"*)
    if [ -n "${MOCK_LABEL_STATE:-}" ] && [ -s "$MOCK_LABEL_STATE" ]; then
      emit "$(jq -R -s '{labels: [split("\n")[] | select(. != "") | {name: .}]}' <"$MOCK_LABEL_STATE")"
    else
      emit "${MOCK_LABELS:-$labels_default}"
    fi
    exit 0
    ;;
  *"pr view"*)
    emit "${MOCK_PR_JSON:-$pr_default}"
    exit 0
    ;;
  *"/check-runs"*)
    [ "${MOCK_CHECK_RUNS_EXIT:-0}" = "0" ] || exit 1
    emit "${MOCK_CHECK_RUNS:-$check_runs_default}"
    exit 0
    ;;
  *"/pulls/"*"/comments"*)
    emit "${MOCK_COMMENTS:-$empty_array}"
    exit 0
    ;;
  *"/pulls/"*"/reviews"*)
    emit "${MOCK_REVIEWS:-$empty_array}"
    exit 0
    ;;
  *"repo view"*)
    emit '{"nameWithOwner":"acme/widgets"}'
    exit 0
    ;;
esac
exit 0
GH
chmod +x "$_BIN/gh"

# A minimal workflow config: bugbot is the ready-phase reviewer, so the helper
# gates on the "Cursor Bugbot" check run and on cursor[bot] findings only.
cat > "$TMP_ROOT/workflow.yaml" <<'YAML'
review:
  on_ready:
    github:
      - bugbot
YAML

HEAD='aaaa111000000000000'
_LABEL_LOG="$TMP_ROOT/gh-calls.log"
_LABEL_STATE="$TMP_ROOT/label-state"

# run_helper — prints "<exit_code>|<stdout>". Payloads come from the MOCK_*
# variables the caller set; a `${VAR:-{...}}` default here would not survive
# parameter expansion, so the fallbacks are plain names.
run_helper() {
  local default_labels='{"labels":[]}'
  : >"$_LABEL_LOG"
  : >"$_LABEL_STATE"
  set +e
  out="$(
    PATH="$_BIN:$PATH" \
    AI_DEV_WORKFLOW_CONFIG_FILE="$TMP_ROOT/workflow.yaml" \
    MOCK_GH_LOG="$_LABEL_LOG" \
    MOCK_LABEL_STATE="$_LABEL_STATE" \
    MOCK_PR_JSON="${MOCK_PR_JSON:-}" \
    MOCK_CHECK_RUNS="${MOCK_CHECK_RUNS:-}" \
    MOCK_COMMENTS="${MOCK_COMMENTS:-[]}" \
    MOCK_REVIEWS="${MOCK_REVIEWS:-[]}" \
    MOCK_LABELS="${MOCK_LABELS:-$default_labels}" \
    MOCK_DROP_LABEL="${MOCK_DROP_LABEL:-0}" \
    "$HELPER" --pr 42 --repo acme/widgets --label ready-for-human-review 2>/dev/null
  )"
  code=$?
  set -e
  printf '%s|%s\n' "$code" "$out"
}

field() {
  printf '%s\n' "${1#*|}" | sed -n "s/^$2=//p" | tail -1
}

edit_count() {
  if [ -s "$_LABEL_LOG" ]; then wc -l <"$_LABEL_LOG" | tr -d ' '; else printf '0'; fi
}

_empty_rollup='{"headRefOid":"'"$HEAD"'","labels":[],"statusCheckRollup":[]}'
_bugbot_ok='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z"}]}'
_bugbot_running='{"check_runs":[{"name":"Cursor Bugbot","status":"in_progress","conclusion":null,"started_at":"2026-01-01T00:00:00Z"}]}'
_bugbot_failed='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"failure","started_at":"2026-01-01T00:00:00Z"}]}'
# A duplicate historical run must not shadow the latest one (#1408 reuses the
# rollup dedupe; this asserts the check-run read picks the newest by started_at).
_bugbot_dup='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"failure","started_at":"2026-01-01T00:00:00Z"},{"name":"Cursor Bugbot","status":"completed","conclusion":"success","started_at":"2026-02-01T00:00:00Z"}]}'
_with_ci() {
  printf '{"headRefOid":"%s","labels":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","workflowName":"ShellCheck","status":"COMPLETED","conclusion":"%s"}]}' "$HEAD" "$1"
}

echo "=== Area 1: refuse on incomplete reviewer verdict ==="

# Planted failing case: reviewer never published a check run for this head.
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS='{"check_runs":[]}'
result="$(run_helper)"
run_test "absent_reviewer_check_exit" "1" "${result%%|*}"
run_test "absent_reviewer_check_reason" "reviewer-check-absent" "$(field "$result" REASON)"
run_test "absent_reviewer_check_result" "refused" "$(field "$result" RESULT)"
run_test "absent_reviewer_check_no_label_applied" "0" "$(edit_count)"

# Reviewer started but has not finished.
MOCK_CHECK_RUNS="$_bugbot_running"
result="$(run_helper)"
run_test "reviewer_not_completed_exit" "1" "${result%%|*}"
run_test "reviewer_not_completed_reason" "reviewer-check-not-completed" "$(field "$result" REASON)"
run_test "reviewer_not_completed_no_label_applied" "0" "$(edit_count)"

# Reviewer completed with blocking findings.
MOCK_CHECK_RUNS="$_bugbot_failed"
MOCK_COMMENTS='[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","in_reply_to_id":null,"body":"**High Severity** leak in the reject path"}]'
result="$(run_helper)"
run_test "blocking_findings_exit" "1" "${result%%|*}"
run_test "blocking_findings_reason" "blocking-findings" "$(field "$result" REASON)"
run_test "blocking_findings_count" "1" "$(field "$result" BLOCKING_FINDING_COUNT)"
run_test "blocking_findings_marked_needs_fixes" "1" "$(grep -c 'add-label needs-fixes' "$_LABEL_LOG" || true)"
run_test "blocking_findings_no_readiness_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"

# A CHANGES_REQUESTED review is blocking regardless of body text.
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","state":"CHANGES_REQUESTED","body":""}]'
result="$(run_helper)"
run_test "changes_requested_exit" "1" "${result%%|*}"
run_test "changes_requested_reason" "blocking-findings" "$(field "$result" REASON)"

echo ""
echo "=== Area 2: refuse on unresolved CI ==="

MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_PR_JSON="$(_with_ci SUCCESS)"
result="$(run_helper)"
run_test "clean_state_exit" "0" "${result%%|*}"
run_test "clean_state_result" "labeled" "$(field "$result" RESULT)"
run_test "clean_state_reason" "gate-passed" "$(field "$result" REASON)"
run_test "clean_state_applies_label" "1" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# Bare `statusCheckRollup: []` is not evidence CI ran; the gate allows it (the
# reviewer check run is read separately) but must never crash on it.
MOCK_PR_JSON="$_empty_rollup"
result="$(run_helper)"
run_test "empty_rollup_exit" "0" "${result%%|*}"

MOCK_PR_JSON='{"headRefOid":"'"$HEAD"'","labels":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","workflowName":"ShellCheck","status":"IN_PROGRESS","conclusion":null}]}'
result="$(run_helper)"
run_test "ci_pending_exit" "1" "${result%%|*}"
run_test "ci_pending_reason" "ci-pending" "$(field "$result" REASON)"
run_test "ci_pending_no_label_applied" "0" "$(edit_count)"

MOCK_PR_JSON="$(_with_ci FAILURE)"
result="$(run_helper)"
run_test "ci_failing_exit" "1" "${result%%|*}"
run_test "ci_failing_reason" "ci-failing" "$(field "$result" REASON)"

# The reviewer's own check run is excluded from the CI classification, so a
# `success` (or a `failure`) Bugbot run never counts as a failing CI check.
MOCK_CHECK_RUNS="$_bugbot_failed"
MOCK_PR_JSON='{"headRefOid":"'"$HEAD"'","labels":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"Cursor Bugbot","workflowName":"Cursor","status":"COMPLETED","conclusion":"FAILURE"}]}'
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
result="$(run_helper)"
run_test "reviewer_check_not_counted_as_ci" "refused" "$(field "$result" RESULT)"
run_test "reviewer_check_excluded_from_ci_counts" "0" "$(field "$result" FAILING_CHECK_COUNT)"

# Latest check-run wins when duplicates exist for the same name.
MOCK_CHECK_RUNS="$_bugbot_dup"
MOCK_PR_JSON="$(_with_ci SUCCESS)"
result="$(run_helper)"
run_test "duplicate_check_run_keeps_latest_exit" "0" "${result%%|*}"

echo ""
echo "=== Area 3: argument validation ==="

set +e
PATH="$_BIN:$PATH" AI_DEV_WORKFLOW_CONFIG_FILE="$TMP_ROOT/workflow.yaml" \
  "$HELPER" --pr 42 --repo acme/widgets --label ready-for-merge >/dev/null 2>&1
code=$?
set -e
run_test "unknown_label_exit" "2" "$code"

set +e
PATH="$_BIN:$PATH" AI_DEV_WORKFLOW_CONFIG_FILE="$TMP_ROOT/workflow.yaml" \
  "$HELPER" --pr abc --repo acme/widgets --label ready-for-human-review >/dev/null 2>&1
code=$?
set -e
run_test "non_numeric_pr_exit" "2" "$code"

set +e
PATH="$_BIN:$PATH" AI_DEV_WORKFLOW_CONFIG_FILE="$TMP_ROOT/workflow.yaml" \
  "$HELPER" --bogus >/dev/null 2>&1
code=$?
set -e
run_test "unknown_arg_exit" "2" "$code"

# A failed state read escalates rather than labelling.
set +e
out="$(PATH="$_BIN:$PATH" AI_DEV_WORKFLOW_CONFIG_FILE="$TMP_ROOT/workflow.yaml" MOCK_GH_LOG="$_LABEL_LOG" MOCK_CHECK_RUNS_EXIT=1 \
  MOCK_PR_JSON="$_empty_rollup" "$HELPER" --pr 42 --repo acme/widgets --label ready-for-human-review 2>/dev/null)"
code=$?
set -e
run_test "check_run_fetch_failure_exit" "2" "$code"
run_test "check_run_fetch_failure_reason" "check-run-fetch-failed" "$(printf '%s\n' "$out" | sed -n 's/^REASON=//p' | tail -1)"

# A label the API silently drops must not be reported as applied.
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_DROP_LABEL=1
result="$(run_helper)"
MOCK_DROP_LABEL=0
run_test "label_not_applied_exit" "2" "${result%%|*}"
run_test "label_not_applied_reason" "label-not-applied" "$(field "$result" REASON)"

echo ""
echo "=== Area 4: protocols forbid hand-applying readiness labels ==="

for protocol in \
  docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md \
  docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
do
  base="$(basename "$protocol")"
  count="$(grep -c -- 'apply-readiness-labels.sh' "$REPO_ROOT/$protocol" || true)"
  run_test "$base references the helper" "1" "$([ "$count" -ge 1 ] && echo 1 || echo 0)"
  hand="$(grep -c 'must not call `gh pr edit --add-label' "$REPO_ROOT/$protocol" || true)"
  run_test "$base forbids direct label application" "1" "$([ "$hand" -ge 1 ] && echo 1 || echo 0)"
done

echo ""
echo "$pass passed, $fail failed"

if [ "$fail" -ne 0 ]; then
  exit 1
fi