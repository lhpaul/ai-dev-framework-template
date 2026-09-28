#!/usr/bin/env bash
# test-apply-readiness-labels.sh - readiness-label gate tests (#1408).
# covers: scripts/development-workflow/apply-readiness-labels.sh
# covers: scripts/development-workflow/workflow-lib.sh
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
# covers: docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
# covers: docs/workflow/development-workflow/protocols/03-implement-development-protocol.md
# covers: docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md
# covers: docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md
# covers: .claude/commands/sync-template.md
# covers: .claude/skills/sync-template.md
# covers: .cursor/commands/sync-template.md
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
# Same SHA as the test-scope BASE_SHA; duplicated here because the quoted
# heredoc does not expand the test script's variables.
_BASE_SHA_STUB='dddd444000000000000'
pr_default='{"headRefOid":"aaaa111000000000000","headRefName":"fix/1408-demo","baseRefOid":"'"$_BASE_SHA_STUB"'","labels":[],"statusCheckRollup":[]}'
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
  *"pr view"*"--json headRefOid --jq"*)
    # Pre-apply head revalidation. MOCK_REVALIDATE_HEAD simulates a push
    # landing between the state read and the label mutation. Logged to a
    # separate call log (not MOCK_GH_LOG, which counts `pr edit` calls only)
    # so the later arms can tell the revalidation fetches from the first.
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    if [ -n "${MOCK_REVALIDATE_HEAD:-}" ]; then
      printf '%s\n' "$MOCK_REVALIDATE_HEAD"
    else
      emit "${MOCK_PR_JSON:-$pr_default}"
    fi
    exit 0
    ;;
  *"pr view"*"--json labels,headRefOid"*)
    # Post-apply verification. MOCK_POST_APPLY_HEAD simulates a push landing
    # during the mutation itself; MOCK_POST_VIEW_EXIT simulates the read
    # failing after `--add-label` already succeeded (PR #1818 finding 3,
    # round 5).
    [ "${MOCK_POST_VIEW_EXIT:-0}" = "0" ] || exit 1
    if [ -n "${MOCK_LABEL_STATE:-}" ] && [ -s "$MOCK_LABEL_STATE" ]; then
      labels_json="$(jq -R -s '{labels: [split("\n")[] | select(. != "") | {name: .}]}' <"$MOCK_LABEL_STATE")"
    else
      labels_json="${MOCK_LABELS:-$labels_default}"
    fi
    head_ref="${MOCK_POST_APPLY_HEAD:-$(printf '%s\n' "${MOCK_PR_JSON:-$pr_default}" | jq -r '.headRefOid // ""')}"
    printf '%s\n' "$labels_json" | jq --arg h "$head_ref" '. + {headRefOid: $h}'
    exit 0
    ;;
  *"pr view"*"--json labels"*)
    if [ -n "${MOCK_LABEL_STATE:-}" ] && [ -s "$MOCK_LABEL_STATE" ]; then
      emit "$(jq -R -s '{labels: [split("\n")[] | select(. != "") | {name: .}]}' <"$MOCK_LABEL_STATE")"
    else
      emit "${MOCK_LABELS:-$labels_default}"
    fi
    exit 0
    ;;
  *"pr view"*"--json headRefOid,headRefName,baseRefOid,labels,statusCheckRollup"*)
    # First fetch (state read) vs the pre-apply revalidation fetch: once the
    # head-revalidate call has run, MOCK_REVALIDATE_PR_JSON (if set) replaces
    # the payload — it simulates a CI check re-triggered on the same head
    # after the verdicts were read (PR #1818 finding 2, round 5).
    if [ -n "${MOCK_REVALIDATE_PR_JSON:-}" ] \
        && grep -q 'pr view 42 --repo acme/widgets --json headRefOid --jq' "${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null; then
      emit "$MOCK_REVALIDATE_PR_JSON"
    else
      emit "${MOCK_PR_JSON:-$pr_default}"
    fi
    exit 0
    ;;
  *"pr view"*)
    emit "${MOCK_PR_JSON:-$pr_default}"
    exit 0
    ;;
  *"/check-runs"*)
    # The helper fetches with `--paginate --slurp`, so gh returns an array of
    # pages. MOCK_CHECK_RUNS may carry several comma-separated page objects.
    # From the second fetch on (the pre-apply revalidation),
    # MOCK_REVALIDATE_CHECK_RUNS (if set) replaces the payload — it simulates a
    # check run re-triggered on the same head after the verdicts were read
    # (PR #1818 finding 2, round 5) — and MOCK_REVALIDATE_CHECK_RUNS_EXIT (if
    # nonzero) fails the revalidation fetch itself (PR #1818 finding 1,
    # round 6).
    # Decide BEFORE appending this call to the log, so the first fetch always
    # sees a log with no prior /check-runs call and gets MOCK_CHECK_RUNS.
    if grep -q '/check-runs' "${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null; then
      [ "${MOCK_REVALIDATE_CHECK_RUNS_EXIT:-0}" = "0" ] || exit 1
      if [ -n "${MOCK_REVALIDATE_CHECK_RUNS:-}" ]; then
        payload="[${MOCK_REVALIDATE_CHECK_RUNS}]"
      else
        payload="[${MOCK_CHECK_RUNS:-$check_runs_default}]"
      fi
    else
      [ "${MOCK_CHECK_RUNS_EXIT:-0}" = "0" ] || exit 1
      payload="[${MOCK_CHECK_RUNS:-$check_runs_default}]"
    fi
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    emit "$payload"
    exit 0
    ;;
  *"/pulls/"*"/comments"*)
    # MOCK_REVALIDATE_COMMENTS (if set) replaces the payload from the second
    # fetch on — the revalidation finding rescan must be able to see findings
    # that did not exist (or were not yet posted) at the first scan (PR #1818
    # finding 2, round 6). Decide BEFORE appending to the call log.
    if [ -n "${MOCK_REVALIDATE_COMMENTS:-}" ] \
        && grep -q '/pulls/42/comments' "${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null; then
      emit "[${MOCK_REVALIDATE_COMMENTS}]"
    else
      emit "[${MOCK_COMMENTS:-$empty_array}]"
    fi
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    exit 0
    ;;
  *"/pulls/"*"/reviews"*)
    emit "[${MOCK_REVIEWS:-$empty_array}]"
    exit 0
    ;;
  *"/issues/"*"/comments"*)
    emit "[${MOCK_ISSUE_COMMENTS:-$empty_array}]"
    exit 0
    ;;
  *"repo view"*)
    emit '{"nameWithOwner":"acme/widgets"}'
    exit 0
    ;;
  *"/contents/.ai-dev-workflow.yaml?ref=$MOCK_BASE_SHA"*)
    # Base-branch configuration fetch (PR #1818 finding 1, round 4). A distinct
    # variable so head and base payloads differ in one invocation.
    [ "${MOCK_BASE_CONFIG_EXIT:-0}" = "0" ] || exit 1
    content="$(printf '%s\n' "${MOCK_BASE_CONFIG:-review:
  on_ready:
    github: []}" | base64)"
    emit "{\"content\":\"$content\"}"
    exit 0
    ;;
  *"/contents/.ai-dev-workflow.yaml"*)
    # PR-head configuration fetch (#1408 finding 1). MOCK_HEAD_CONFIG carries
    # the raw YAML body; MOCK_HEAD_CONFIG_EXIT simulates the API failure.
    [ "${MOCK_HEAD_CONFIG_EXIT:-0}" = "0" ] || exit 1
    content="$(printf '%s\n' "${MOCK_HEAD_CONFIG:-review:
  on_ready:
    github:
      - bugbot}" | base64)"
    emit "{\"content\":\"$content\"}"
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
BASE_SHA='dddd444000000000000'
_BRANCH='fix/1408-demo'
_LABEL_LOG="$TMP_ROOT/gh-calls.log"
_CALL_LOG="$TMP_ROOT/gh-all-calls.log"
_LABEL_STATE="$TMP_ROOT/label-state"

# run_helper — prints "<exit_code>|<stdout>". Payloads come from the MOCK_*
# variables the caller set; a `${VAR:-{...}}` default here would not survive
# parameter expansion, so the fallbacks are plain names.
run_helper() {
  local default_labels='{"labels":[]}'
  local label="${MOCK_LABEL:-ready-for-human-review}"
  : >"$_LABEL_LOG"
  : >"$_LABEL_STATE"
  : >"$_CALL_LOG"
  set +e
  out="$(
    PATH="$_BIN:$PATH" \
    AI_DEV_WORKFLOW_CONFIG_FILE="$TMP_ROOT/workflow.yaml" \
    MOCK_GH_LOG="$_LABEL_LOG" \
    MOCK_CALL_LOG="$_CALL_LOG" \
    MOCK_LABEL_STATE="$_LABEL_STATE" \
    MOCK_PR_JSON="${MOCK_PR_JSON:-}" \
    MOCK_CHECK_RUNS="${MOCK_CHECK_RUNS:-}" \
    MOCK_COMMENTS="${MOCK_COMMENTS:-[]}" \
    MOCK_REVIEWS="${MOCK_REVIEWS:-[]}" \
    MOCK_LABELS="${MOCK_LABELS:-$default_labels}" \
    MOCK_ISSUE_COMMENTS="${MOCK_ISSUE_COMMENTS:-[]}" \
    MOCK_REVALIDATE_HEAD="${MOCK_REVALIDATE_HEAD:-}" \
    MOCK_POST_APPLY_HEAD="${MOCK_POST_APPLY_HEAD:-}" \
    MOCK_DROP_LABEL="${MOCK_DROP_LABEL:-0}" \
    MOCK_HEAD_CONFIG="${MOCK_HEAD_CONFIG:-}" \
    MOCK_HEAD_CONFIG_EXIT="${MOCK_HEAD_CONFIG_EXIT:-0}" \
    MOCK_BASE_SHA="$BASE_SHA" \
    MOCK_BASE_CONFIG="${MOCK_BASE_CONFIG:-}" \
    MOCK_BASE_CONFIG_EXIT="${MOCK_BASE_CONFIG_EXIT:-0}" \
    MOCK_REVALIDATE_CHECK_RUNS="${MOCK_REVALIDATE_CHECK_RUNS:-}" \
    MOCK_REVALIDATE_PR_JSON="${MOCK_REVALIDATE_PR_JSON:-}" \
    MOCK_REVALIDATE_COMMENTS="${MOCK_REVALIDATE_COMMENTS:-}" \
    MOCK_REVALIDATE_CHECK_RUNS_EXIT="${MOCK_REVALIDATE_CHECK_RUNS_EXIT:-0}" \
    MOCK_POST_VIEW_EXIT="${MOCK_POST_VIEW_EXIT:-0}" \
    "$HELPER" --pr 42 --repo acme/widgets --label "$label" 2>/dev/null
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

_empty_rollup='{"headRefOid":"'"$HEAD"'","headRefName":"'"$_BRANCH"'","baseRefOid":"'"$BASE_SHA"'","labels":[],"statusCheckRollup":[]}'
_bugbot_ok='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z"}]}'
_bugbot_running='{"check_runs":[{"name":"Cursor Bugbot","status":"in_progress","conclusion":null,"started_at":"2026-01-01T00:00:00Z"}]}'
_bugbot_failed='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"failure","started_at":"2026-01-01T00:00:00Z"}]}'
# A duplicate historical run must not shadow the latest one (#1408 reuses the
# rollup dedupe; this asserts the check-run read picks the newest by started_at).
_bugbot_dup='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"failure","started_at":"2026-01-01T00:00:00Z"},{"name":"Cursor Bugbot","status":"completed","conclusion":"success","started_at":"2026-02-01T00:00:00Z"}]}'
# Bugbot's quota refusal: a `neutral` check run plus a usage-limit issue comment.
# Observed on PR #1818; a bare `neutral` previously read as clean.
_bugbot_neutral='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"neutral","started_at":"2026-01-01T00:00:00Z"}]}'
_usage_limit_comment='[{"user":{"login":"cursor[bot]"},"created_at":"2026-01-02T00:00:00Z","body":"<h3>Bugbot couldn'\''t run - usage limit reached</h3>"}]'
_with_ci() {
  printf '{"headRefOid":"%s","headRefName":"%s","labels":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","workflowName":"ShellCheck","status":"COMPLETED","conclusion":"%s"}]}' "$HEAD" "$_BRANCH" "$1"
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
MOCK_REVIEWS='[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","state":"CHANGES_REQUESTED","body":"","submitted_at":"2026-01-02T00:00:00Z"}]'
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

MOCK_PR_JSON='{"headRefOid":"'"$HEAD"'","headRefName":"'"$_BRANCH"'","labels":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","workflowName":"ShellCheck","status":"IN_PROGRESS","conclusion":null}]}'
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
MOCK_PR_JSON='{"headRefOid":"'"$HEAD"'","headRefName":"'"$_BRANCH"'","labels":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"Cursor Bugbot","workflowName":"Cursor","status":"COMPLETED","conclusion":"FAILURE"}]}'
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

# A `neutral` Bugbot check is clean ONLY when no unavailable notice exists for
# the head. These two assertions are the planted failing case for PR #1818,
# where a bare `neutral` was read as a clean reviewer verdict.
MOCK_CHECK_RUNS="$_bugbot_neutral"
MOCK_ISSUE_COMMENTS="$_usage_limit_comment"
MOCK_PR_JSON="$(_with_ci SUCCESS)"
result="$(run_helper)"
run_test "neutral_with_usage_limit_exit" "1" "${result%%|*}"
run_test "neutral_with_usage_limit_reason" "reviewer-unavailable" "$(field "$result" REASON)"
run_test "neutral_with_usage_limit_no_label" "0" "$(edit_count)"
MOCK_ISSUE_COMMENTS='[]'
result="$(run_helper)"
run_test "neutral_without_notice_exit" "0" "${result%%|*}"
run_test "neutral_without_notice_result" "labeled" "$(field "$result" RESULT)"
# A notice older than the check run must not refuse a genuine neutral verdict.
MOCK_ISSUE_COMMENTS='[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-01T00:00:00Z","body":"Bugbot couldn'\''t run - usage limit reached"}]'
result="$(run_helper)"
run_test "stale_notice_does_not_refuse" "labeled" "$(field "$result" RESULT)"
MOCK_ISSUE_COMMENTS='[]'

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
  hand="$(grep -c 'must not call `gh pr edit --add-label' "$REPO_ROOT/$protocol" || true)"  # workflow-shell-guard: allow SH001 - grep -c exits 1 on zero matches; the assertion on the next line decides pass/fail.
  run_test "$base forbids direct label application" "1" "$([ "$hand" -ge 1 ] && echo 1 || echo 0)"
done

# Residual check: no normative surface still instructs a bare
# `gh pr edit ... --add-label "ready-for-*"`. The release protocol is the one
# documented exemption (release PRs have no reviewer check run), so it must
# carry the exemption note instead.
for surface in \
  docs/workflow/development-workflow/protocols/03-implement-development-protocol.md \
  docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md \
  .claude/commands/sync-template.md \
  .claude/skills/sync-template.md \
  .cursor/commands/sync-template.md
do
  bare="$(grep -c 'add-label "ready-for-' "$REPO_ROOT/$surface" || true)"
  run_test "$surface has no bare ready-* apply" "0" "$bare"
done

release_surface="docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md"
run_test "05 documents the release exemption" "1" \
  "$([ "$(grep -c 'documented exemption from helper-gated readiness labels' "$REPO_ROOT/$release_surface" || true)" -ge 1 ] && echo 1 || echo 0)"

echo ""
echo "=== Area 5: branch-type scope for the reviewer leg ==="

# Ready-phase reviewers are not dispatched on doc-stage branches, so no check run
# can exist for them. Gating on one would refuse every spec/plan PR — the exact
# behaviour this assertion locks out.
MOCK_LABEL='ready-for-human-review'
MOCK_CHECK_RUNS='{"check_runs":[]}'
MOCK_PR_JSON='{"headRefOid":"'"$HEAD"'","headRefName":"spec/1408-demo","labels":[],"statusCheckRollup":[]}'
result="$(run_helper)"
run_test "spec_branch_not_reviewer_gated_exit" "0" "${result%%|*}"
run_test "spec_branch_not_reviewer_gated_result" "labeled" "$(field "$result" RESULT)"

MOCK_PR_JSON='{"headRefOid":"'"$HEAD"'","headRefName":"implementation-plan/1408-demo","labels":[],"statusCheckRollup":[]}'
result="$(run_helper)"
run_test "plan_branch_not_reviewer_gated_exit" "0" "${result%%|*}"
run_test "plan_branch_reviewer_report" "none" "$(field "$result" REVIEWER_REPORT)"

# An implementation branch with the same empty check-run set still refuses: the
# exemption must be scoped to branch type, not to "check run missing".
MOCK_PR_JSON="$_empty_rollup"
result="$(run_helper)"
run_test "impl_branch_still_reviewer_gated_exit" "1" "${result%%|*}"
run_test "impl_branch_still_reviewer_gated_reason" "reviewer-check-absent" "$(field "$result" REASON)"

# `ready-for-regression` is applied at Step 7b, before the Step 8 CI loop, so a
# pending check is normal there. Refusing on it would deadlock Step 7b against
# the very checks the label starts.
MOCK_LABEL='ready-for-regression'
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_PR_JSON='{"headRefOid":"'"$HEAD"'","headRefName":"'"$_BRANCH"'","labels":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","workflowName":"ShellCheck","status":"IN_PROGRESS","conclusion":null}]}'
result="$(run_helper)"
run_test "regression_label_allows_pending_ci_exit" "0" "${result%%|*}"
run_test "regression_label_allows_pending_ci_result" "labeled" "$(field "$result" RESULT)"
# A failing check still refuses under either label.
MOCK_PR_JSON="$(_with_ci FAILURE)"
result="$(run_helper)"
run_test "regression_label_still_refuses_failing_ci" "ci-failing" "$(field "$result" REASON)"
MOCK_LABEL=''

echo ""
echo "=== Area 6: PR #1818 Codex findings ==="

# Finding 1 (P1): a ready-phase platform with no check-name mapping must be
# refused, not silently skipped — the documented default ready reviewer in this
# repo (codex-github) is exactly such a platform.
mkdir -p "$TMP_ROOT/codex-config"
cat > "$TMP_ROOT/codex-config/workflow.yaml" <<'YAML'
review:
  on_ready:
    github:
      - codex-github
YAML
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS='{"check_runs":[]}'
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
set +e
out="$(
  PATH="$_BIN:$PATH" \
  AI_DEV_WORKFLOW_CONFIG_FILE="$TMP_ROOT/codex-config/workflow.yaml" \
  MOCK_GH_LOG="$_LABEL_LOG" MOCK_LABEL_STATE="$_LABEL_STATE" \
  MOCK_CHECK_RUNS='{"check_runs":[]}' MOCK_COMMENTS='[]' MOCK_REVIEWS='[]' \
  "$HELPER" --pr 42 --repo acme/widgets --label ready-for-human-review 2>/dev/null
)"
code=$?
set -e
run_test "unresolved_platform_exit" "1" "$code"
run_test "unresolved_platform_reason" "reviewer-check-name-unresolved" "$(printf '%s\n' "$out" | sed -n 's/^REASON=//p' | tail -1)"
run_test "unresolved_platform_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "unresolved_platform_names_platform" "codex-github" "$(printf '%s\n' "$out" | sed -n 's/^REVIEWER_REPORT=//p' | tail -1)"

# Finding 2 (P1): the head must be revalidated immediately before the label
# mutation; a push landing between the state read and the apply must refuse.
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[]'
MOCK_REVALIDATE_HEAD='bbbb222000000000000'
result="$(run_helper)"
MOCK_REVALIDATE_HEAD=''
run_test "head_changed_before_apply_exit" "1" "${result%%|*}"
run_test "head_changed_before_apply_reason" "head-changed-before-apply" "$(field "$result" REASON)"
run_test "head_changed_before_apply_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"

# Same guard after the apply: the label must not certify an undrifting head.
MOCK_REVALIDATE_HEAD=''
MOCK_POST_APPLY_HEAD='cccc333000000000000'
result="$(run_helper)"
MOCK_POST_APPLY_HEAD=''
run_test "head_changed_after_apply_exit" "2" "${result%%|*}"
run_test "head_changed_after_apply_reason" "head-changed-after-apply" "$(field "$result" REASON)"

# Finding 3 (P2): `gh api --paginate` emits one JSON object per page; the
# check-run read must flatten all pages. First page carries a `failure` run for
# the reviewer; a per-page jq pipeline would corrupt the conclusion (e.g.
# "failure\n ") and miss the blocking case. (The stub emits MOCK_CHECK_RUNS as
# pages of a `--slurp` array.)
MOCK_PR_JSON="$(_with_ci SUCCESS)"
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[]'
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"failure","started_at":"2026-01-01T00:00:00Z"}]},{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"success","started_at":"2026-02-01T00:00:00Z"}]}'
result="$(run_helper)"
run_test "paginated_check_runs_keep_latest_exit" "0" "${result%%|*}"
run_test "paginated_check_runs_keep_latest_result" "labeled" "$(field "$result" RESULT)"
# Same defect class on the finding surfaces: a blocking review found on a later
# page must still refuse.
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_REVIEWS='[],[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","state":"CHANGES_REQUESTED","body":"","submitted_at":"2026-01-02T00:00:00Z"}]'
result="$(run_helper)"
run_test "paginated_reviews_later_page_still_blocks_exit" "1" "${result%%|*}"
run_test "paginated_reviews_later_page_still_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
# and a later-page inline finding likewise.
MOCK_REVIEWS='[]'
MOCK_COMMENTS='[],[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","in_reply_to_id":null,"body":"**High Severity** leak","created_at":"2026-01-02T00:00:00Z"}]'
result="$(run_helper)"
run_test "paginated_comments_later_page_still_blocks_exit" "1" "${result%%|*}"
run_test "paginated_comments_later_page_still_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
MOCK_COMMENTS='[]'

echo ""
echo "=== Area 7: PR #1818 Codex findings, round 2 ==="

# Finding 1 (P1): the ready-phase platform list must be read from the PR head's
# own .ai-dev-workflow.yaml, not this checkout. The test's local config file
# declares bugbot; the PR head config declares ronda. A local-config read gates
# on "Cursor Bugbot" (absent → refuse); a head-config read gates on "Ronda
# review" (present and clean → labeled). run_helper keeps
# AI_DEV_WORKFLOW_CONFIG_FILE set for the other areas; here it is unset so the
# head-config path runs.
run_helper_no_local_config() {
  local label="${MOCK_LABEL:-ready-for-human-review}"
  : >"$_LABEL_LOG"
  : >"$_LABEL_STATE"
  : >"$_CALL_LOG"
  set +e
  out="$(
    PATH="$_BIN:$PATH" \
    MOCK_GH_LOG="$_LABEL_LOG" \
    MOCK_CALL_LOG="$_CALL_LOG" \
    MOCK_LABEL_STATE="$_LABEL_STATE" \
    MOCK_PR_JSON="${MOCK_PR_JSON:-}" \
    MOCK_CHECK_RUNS="${MOCK_CHECK_RUNS:-}" \
    MOCK_COMMENTS="${MOCK_COMMENTS:-[]}" \
    MOCK_REVIEWS="${MOCK_REVIEWS:-[]}" \
    MOCK_LABELS='{"labels":[]}' \
    MOCK_ISSUE_COMMENTS="${MOCK_ISSUE_COMMENTS:-[]}" \
    MOCK_REVALIDATE_HEAD="${MOCK_REVALIDATE_HEAD:-}" \
    MOCK_POST_APPLY_HEAD="${MOCK_POST_APPLY_HEAD:-}" \
    MOCK_DROP_LABEL="${MOCK_DROP_LABEL:-0}" \
    MOCK_HEAD_CONFIG="${MOCK_HEAD_CONFIG:-}" \
    MOCK_HEAD_CONFIG_EXIT="${MOCK_HEAD_CONFIG_EXIT:-0}" \
    MOCK_BASE_SHA="$BASE_SHA" \
    MOCK_BASE_CONFIG="${MOCK_BASE_CONFIG:-}" \
    MOCK_BASE_CONFIG_EXIT="${MOCK_BASE_CONFIG_EXIT:-0}" \
    MOCK_REVALIDATE_CHECK_RUNS="${MOCK_REVALIDATE_CHECK_RUNS:-}" \
    MOCK_REVALIDATE_PR_JSON="${MOCK_REVALIDATE_PR_JSON:-}" \
    MOCK_REVALIDATE_COMMENTS="${MOCK_REVALIDATE_COMMENTS:-}" \
    MOCK_REVALIDATE_CHECK_RUNS_EXIT="${MOCK_REVALIDATE_CHECK_RUNS_EXIT:-0}" \
    MOCK_POST_VIEW_EXIT="${MOCK_POST_VIEW_EXIT:-0}" \
    "$HELPER" --pr 42 --repo acme/widgets --label "$label" 2>/dev/null
  )"
  code=$?
  set -e
  printf '%s|%s\n' "$code" "$out"
}

MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Ronda review","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z"}]}'
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[]'
MOCK_HEAD_CONFIG='review:
  on_ready:
    github:
      - ronda'
result="$(run_helper_no_local_config)"
run_test "pr_head_config_platforms_exit" "0" "${result%%|*}"
run_test "pr_head_config_platforms_result" "labeled" "$(field "$result" RESULT)"
# ...and a head-config fetch failure must not silently fall back to the local
# checkout's platform list (the local file here still declares bugbot and its
# check run is present-and-clean, so a fallback would label): it escalates
# fail-closed. This is the planted failing case for finding 1.
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_HEAD_CONFIG_EXIT=1
result="$(run_helper_no_local_config)"
MOCK_HEAD_CONFIG_EXIT=0
run_test "head_config_unreadable_escalates_exit" "2" "${result%%|*}"
run_test "head_config_unreadable_reason" "ready-config-unreadable" "$(field "$result" REASON)"
run_test "head_config_unreadable_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"

# Finding 2 (P1): post-apply head drift must remove the label it can no longer
# certify, not just escalate and leave it on the unreviewed head.
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_POST_APPLY_HEAD='cccc333000000000000'
result="$(run_helper)"
MOCK_POST_APPLY_HEAD=''
run_test "head_drift_removes_label" "1" "$(grep -c -- '--remove-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "head_drift_still_escalates_exit" "2" "${result%%|*}"
run_test "head_drift_still_escalates_reason" "head-changed-after-apply" "$(field "$result" REASON)"

# Finding 5 (P2): findings are time-bounded to the selected check run's
# started_at. A stale same-SHA comment from BEFORE the reviewer run must not
# block forever; a fresh one still does.
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"success","started_at":"2026-03-01T00:00:00Z"}]}'
MOCK_COMMENTS='[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","in_reply_to_id":null,"created_at":"2026-02-01T00:00:00Z","body":"**High Severity** stale finding from an earlier run"}]'
result="$(run_helper)"
run_test "stale_same_sha_comment_ignored_exit" "0" "${result%%|*}"
run_test "stale_same_sha_comment_ignored_result" "labeled" "$(field "$result" RESULT)"
MOCK_COMMENTS='[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","in_reply_to_id":null,"created_at":"2026-03-02T00:00:00Z","body":"**High Severity** fresh finding"}]'
result="$(run_helper)"
run_test "fresh_same_sha_comment_blocks_exit" "1" "${result%%|*}"
run_test "fresh_same_sha_comment_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
MOCK_COMMENTS='[]'
# Same boundary on the review surface: a CHANGES_REQUESTED review submitted
# before the check run started is stale; one submitted after still blocks.
MOCK_REVIEWS='[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","state":"CHANGES_REQUESTED","body":"","submitted_at":"2026-02-01T00:00:00Z"}]'
result="$(run_helper)"
run_test "stale_same_sha_review_ignored_result" "labeled" "$(field "$result" RESULT)"
MOCK_REVIEWS='[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","state":"CHANGES_REQUESTED","body":"","submitted_at":"2026-03-02T00:00:00Z"}]'
result="$(run_helper)"
run_test "fresh_same_sha_review_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
MOCK_REVIEWS='[]'

# Finding 4 (P2): the helper must be declared as a product-repo injection
# entry in both sync manifests, or product repos routed implementation work
# will not receive it and their readiness labels fall back to hand-applies.
_sync_entry="$(grep -c 'apply-readiness-labels.sh' "$REPO_ROOT/sync-manifest.yaml" || true)"
run_test "sync_manifest_declares_helper" "1" "$([ "$_sync_entry" -ge 1 ] && echo 1 || echo 0)"
_skeleton_entry="$(grep -c 'apply-readiness-labels.sh' "$REPO_ROOT/template/product-repo-injection/skeleton-manifest.yaml" || true)"
run_test "skeleton_manifest_declares_helper" "1" "$([ "$_skeleton_entry" -ge 1 ] && echo 1 || echo 0)"
unset _sync_entry _skeleton_entry

echo ""
echo "=== Area 8: PR #1818 Codex findings, round 3 ==="

# Finding 1 (P1): only Bugbot reports reviewer unavailability through an issue
# comment. For any other configured platform (ronda, haystack), a completed
# check run concluding neutral/cancelled/skipped means the reviewer never
# finished a successful review, and must be refused fail-closed — previously
# the code only probed issue comments when platform=bugbot and fell through
# clean otherwise. Planted failing case for the round-3 fix. (Round-6
# semantics: the required set is the BASE policy, so these cases declare
# ronda on the base branch as well — a head-only ronda addition would not be
# gated at all.)
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Ronda review","status":"completed","conclusion":"neutral","started_at":"2026-01-01T00:00:00Z"}]}'
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[]'
MOCK_HEAD_CONFIG='review:
  on_ready:
    github:
      - ronda'
MOCK_BASE_CONFIG='review:
  on_ready:
    github:
      - ronda'
result="$(run_helper_no_local_config)"
run_test "ronda_neutral_refused_exit" "1" "${result%%|*}"
run_test "ronda_neutral_refused_reason" "reviewer-unavailable" "$(field "$result" REASON)"
run_test "ronda_neutral_refused_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# Same rule for cancelled and skipped conclusions.
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Ronda review","status":"completed","conclusion":"cancelled","started_at":"2026-01-01T00:00:00Z"}]}'
result="$(run_helper_no_local_config)"
run_test "ronda_cancelled_refused_reason" "reviewer-unavailable" "$(field "$result" REASON)"
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Ronda review","status":"completed","conclusion":"skipped","started_at":"2026-01-01T00:00:00Z"}]}'
result="$(run_helper_no_local_config)"
run_test "ronda_skipped_refused_reason" "reviewer-unavailable" "$(field "$result" REASON)"
MOCK_HEAD_CONFIG=''
MOCK_BASE_CONFIG=''
# Bugbot keeps its notice-probe semantics: a bare neutral with no notice is
# still clean (covered in Area 1); the fail-closed branch is non-bugbot only.
MOCK_CHECK_RUNS="$_bugbot_neutral"
MOCK_ISSUE_COMMENTS='[]'
result="$(run_helper)"
run_test "bugbot_neutral_no_notice_still_clean" "labeled" "$(field "$result" RESULT)"
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_ISSUE_COMMENTS='[]'

echo ""
echo "=== Area 9: PR #1818 Codex findings, round 4 ==="

# Finding 1 (P1): an implementation PR whose head resolves an EMPTY ready
# platform list (e.g. the PR removes `review.on_ready.github`) previously
# ran the reviewer while-loop zero times and applied the label with
# REVIEWER_REPORT=none — zero reviewer gates. The head-config fetch (local
# config unset) is followed by a base-branch fetch: when the base still
# declares a ready reviewer, the label must refuse as
# reviewer-policy-empty. Planted failing case.
MOCK_PR_JSON="$_empty_rollup"
MOCK_HEAD_CONFIG='review:
  on_ready:
    github: []'
MOCK_BASE_CONFIG='review:
  on_ready:
    github:
      - ronda'
result="$(run_helper_no_local_config)"
run_test "empty_head_platform_list_exit" "1" "${result%%|*}"
run_test "empty_head_platform_list_reason" "reviewer-policy-empty" "$(field "$result" REASON)"
run_test "empty_head_platform_list_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "empty_head_platform_list_names_base" "base-declares:ronda" "$(field "$result" REVIEWER_REPORT)"
# Both head and base empty: base branch has no ready-phase reviewers, so no
# reviewer gate is being waived — CI-only gate applies and the label is clean.
MOCK_BASE_CONFIG='review:
  on_ready:
    github: []'
result="$(run_helper_no_local_config)"
run_test "both_policies_empty_exit" "0" "${result%%|*}"
run_test "both_policies_empty_result" "labeled" "$(field "$result" RESULT)"
# Base-config fetch failure must escalate fail-closed, not waive the gate.
MOCK_BASE_CONFIG_EXIT=1
result="$(run_helper_no_local_config)"
MOCK_BASE_CONFIG_EXIT=0
run_test "base_config_unreadable_escalates_exit" "2" "${result%%|*}"
run_test "base_config_unreadable_reason" "base-config-unreadable" "$(field "$result" REASON)"
MOCK_HEAD_CONFIG=''
MOCK_BASE_CONFIG=''

# Finding 2 (P1): only `success` is a clean reviewer conclusion. `stale` and
# any other unrecognized non-empty conclusion previously matched neither the
# blocking case arm nor the neutral/cancelled/skipped arm and fell through as
# clean. Planted failing case: conclusion `stale`.
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"stale","started_at":"2026-01-01T00:00:00Z"}]}'
result="$(run_helper)"
run_test "stale_conclusion_exit" "1" "${result%%|*}"
run_test "stale_conclusion_reason" "reviewer-check-unknown-conclusion" "$(field "$result" REASON)"
run_test "stale_conclusion_no_label" "0" "$(edit_count)"
run_test "stale_conclusion_reported" "Cursor Bugbot conclusion:stale" "$(field "$result" REVIEWER_REPORT)"
# Any other unrecognized conclusion refuses the same way.
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"robotaborted","started_at":"2026-01-01T00:00:00Z"}]}'
result="$(run_helper)"
run_test "unexpected_conclusion_reason" "reviewer-check-unknown-conclusion" "$(field "$result" REASON)"
MOCK_CHECK_RUNS="$_bugbot_ok"

echo ""
echo "=== Area 10: PR #1818 Codex findings, round 5 ==="

# Reset to the clean default before the planted cases.
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[]'

# Finding 1 (P1): the base-and-head reviewer policy. The round-4 fix only
# fetched the base policy when the head list was empty, so a PR that
# *replaced* a base-configured reviewer (base `ronda` -> head `bugbot`)
# never fetched the base config and silently waived the base-configured
# reviewer. The required set is the BASE policy: the "Ronda review" check run
# is absent here, so the label must refuse as reviewer-check-absent, not
# apply after a clean Bugbot verdict alone. Planted failing case for the
# round-5 fix.
MOCK_HEAD_CONFIG='review:
  on_ready:
    github:
      - bugbot'
MOCK_BASE_CONFIG='review:
  on_ready:
    github:
      - ronda'
MOCK_CHECK_RUNS="$_bugbot_ok"
result="$(run_helper_no_local_config)"
run_test "base_head_union_missing_base_reviewer_exit" "1" "${result%%|*}"
run_test "base_head_union_missing_base_reviewer_reason" "reviewer-check-absent" "$(field "$result" REASON)"
run_test "base_head_union_missing_base_reviewer_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# Base-policy gating: the base reviewer's check run is present and clean, so
# the label applies even though the head-only addition (bugbot) carries no
# check run — the loop dispatches ready-phase platforms from the BASE
# configuration, so a head-only added reviewer never runs and must not be
# required (round-6 semantics).
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Ronda review","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z"}]}'
result="$(run_helper_no_local_config)"
run_test "base_clean_head_addition_absent_exit" "0" "${result%%|*}"
run_test "base_clean_head_addition_absent_result" "labeled" "$(field "$result" RESULT)"
run_test "base_policy_names_base_only" "Ronda review" "$(field "$result" REVIEWER_REPORT)"
# The base-config fetch now runs on EVERY implementation-PR invocation (not
# only when the head list is empty), so a failed base fetch must escalate
# even though the head policy is nonempty.
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_BASE_CONFIG_EXIT=1
result="$(run_helper_no_local_config)"
MOCK_BASE_CONFIG_EXIT=0
run_test "nonempty_head_base_fetch_failure_escalates_exit" "2" "${result%%|*}"
run_test "nonempty_head_base_fetch_failure_reason" "base-config-unreadable" "$(field "$result" REASON)"
MOCK_HEAD_CONFIG=''
MOCK_BASE_CONFIG=''
MOCK_CHECK_RUNS="$_bugbot_ok"

# Finding 2 (P1): stale check state at apply time. A reviewer check run
# re-triggered on the SAME head after the verdicts were read (success ->
# in_progress) must refuse: re-checking only `headRefOid` applied the label
# from stale success data. The stub serves MOCK_CHECK_RUNS for the verdict
# fetch and MOCK_REVALIDATE_CHECK_RUNS for the pre-apply revalidation fetch.
MOCK_REVALIDATE_CHECK_RUNS="$_bugbot_running"
result="$(run_helper)"
run_test "reviewer_rerun_stale_success_exit" "1" "${result%%|*}"
run_test "reviewer_rerun_stale_success_reason" "reviewer-state-changed" "$(field "$result" REASON)"
run_test "reviewer_rerun_stale_success_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
MOCK_REVALIDATE_CHECK_RUNS="$_bugbot_failed"
result="$(run_helper)"
run_test "reviewer_rerun_failure_reason" "reviewer-state-changed" "$(field "$result" REASON)"
MOCK_REVALIDATE_CHECK_RUNS=''
# A clean revalidation payload must keep labelling (regression guard: the
# re-fetch must not refuse a still-clean state).
MOCK_REVALIDATE_CHECK_RUNS="$_bugbot_ok"
result="$(run_helper)"
run_test "clean_revalidation_still_labels" "labeled" "$(field "$result" RESULT)"
MOCK_REVALIDATE_CHECK_RUNS=''
# CI rerun mid-run: the pre-apply statusCheckRollup re-read must still
# satisfy the same pending/failing rule the main gate applied.
MOCK_REVALIDATE_PR_JSON='{"headRefOid":"'"$HEAD"'","headRefName":"'"$_BRANCH"'","labels":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","workflowName":"ShellCheck","status":"IN_PROGRESS","conclusion":null}]}'
result="$(run_helper)"
run_test "ci_rerun_pending_refuses_exit" "1" "${result%%|*}"
run_test "ci_rerun_pending_refuses_reason" "reviewer-state-changed" "$(field "$result" REASON)"
run_test "ci_rerun_pending_refuses_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# A reviewer check run that has DISAPPEARED by revalidation time (re-run
# deleted, or the re-fetch returns no runs) is no longer a completed clean
# run, so the label must refuse rather than trust the earlier verdict.
MOCK_REVALIDATE_PR_JSON=''
MOCK_REVALIDATE_CHECK_RUNS='{"check_runs":[]}'
result="$(run_helper)"
run_test "unreadable_revalidation_refuses_exit" "1" "${result%%|*}"
run_test "unreadable_revalidation_refuses_reason" "reviewer-state-changed" "$(field "$result" REASON)"
MOCK_REVALIDATE_CHECK_RUNS=""
MOCK_CHECK_RUNS="$_bugbot_ok"

echo ""
echo "=== Area 11: PR #1818 Codex findings, round 6 ==="

# Reset to the clean default before the planted cases.
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[]'
MOCK_REVALIDATE_PR_JSON=''
MOCK_REVALIDATE_COMMENTS=''

# Finding 1 (P1): a failed revalidation check-run fetch must escalate
# fail-closed (revalidation-unreadable), never read as success. Previously
# the function returned 0 on a failed or empty re-fetch, so the label applied
# from a potentially stale verdict. Planted failing case.
MOCK_REVALIDATE_CHECK_RUNS_EXIT=1
result="$(run_helper)"
MOCK_REVALIDATE_CHECK_RUNS_EXIT=0
run_test "revalidation_fetch_failure_escalates_exit" "2" "${result%%|*}"
run_test "revalidation_fetch_failure_reason" "revalidation-unreadable" "$(field "$result" REASON)"
run_test "revalidation_fetch_failure_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# A readable clean revalidation still labels (regression guard, round 5).
MOCK_REVALIDATE_CHECK_RUNS="$_bugbot_ok"
result="$(run_helper)"
run_test "round6_clean_revalidation_still_labels" "labeled" "$(field "$result" RESULT)"
MOCK_REVALIDATE_CHECK_RUNS=''

# Finding 2 (P1): a same-SHA rerun that completes between the initial finding
# scan and the revalidation can conclude `success` while posting blocking
# findings the first scan never saw. The revalidation must rescan the finding
# surfaces against the newly selected run's timestamp. Planted failing case:
# the rerun's check run is NEWER (started 2026-04-01) than the first scan's
# (2026-01-01), the rerun posts a fresh blocking comment (2026-04-02), and
# the label must refuse instead of applying from the superseded run's clean
# scan.
MOCK_REVALIDATE_CHECK_RUNS='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"success","started_at":"2026-04-01T00:00:00Z"}]}'
MOCK_REVALIDATE_COMMENTS='[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","in_reply_to_id":null,"created_at":"2026-04-02T00:00:00Z","body":"**High Severity** fresh finding from the rerun"}]'
result="$(run_helper)"
run_test "rerun_newer_run_fresh_findings_refuse_exit" "1" "${result%%|*}"
run_test "rerun_newer_run_fresh_findings_reason" "reviewer-state-changed" "$(field "$result" REASON)"
run_test "rerun_newer_run_fresh_findings_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# Same selected run (same started_at), but a blocking comment appeared after
# the first scan: comment bodies are mutable, so the rescan must catch it.
MOCK_REVALIDATE_CHECK_RUNS="$_bugbot_ok"
MOCK_REVALIDATE_COMMENTS='[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","in_reply_to_id":null,"created_at":"2026-01-02T00:00:00Z","body":"**High Severity** posted after the first scan"}]'
result="$(run_helper)"
run_test "same_run_late_comment_still_refuses_reason" "reviewer-state-changed" "$(field "$result" REASON)"
MOCK_REVALIDATE_COMMENTS=''
# A rerun that concludes neutral with a fresh Bugbot usage-limit notice must
# also refuse: the notice probe is repeated at revalidation.
MOCK_REVALIDATE_CHECK_RUNS='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"neutral","started_at":"2026-04-01T00:00:00Z"}]}'
MOCK_ISSUE_COMMENTS='[{"user":{"login":"cursor[bot]"},"created_at":"2026-04-02T00:00:00Z","body":"<h3>Bugbot couldn'\''t run - usage limit reached</h3>"}]'
result="$(run_helper)"
run_test "rerun_neutral_with_notice_refuses_reason" "reviewer-state-changed" "$(field "$result" REASON)"
MOCK_ISSUE_COMMENTS='[]'
MOCK_REVALIDATE_CHECK_RUNS=''

# Finding 3 (P2): the round-5 union required head-only ADDITIONS. A config PR
# that adds a ready-phase reviewer (base bugbot, head bugbot+haystack) is
# permanently refused reviewer-check-absent because the loop only dispatches
# base-configured platforms. Required set = base policy; the head cannot
# waive a base reviewer, but head-only additions are not required. Planted
# failing case: head adds haystack, no "Haystack / Review" check run exists,
# base bugbot is clean — the label must apply.
MOCK_HEAD_CONFIG='review:
  on_ready:
    github:
      - bugbot
      - haystack'
MOCK_BASE_CONFIG='review:
  on_ready:
    github:
      - bugbot'
MOCK_CHECK_RUNS="$_bugbot_ok"
result="$(run_helper_no_local_config)"
run_test "head_addition_not_required_exit" "0" "${result%%|*}"
run_test "head_addition_not_required_result" "labeled" "$(field "$result" RESULT)"
run_test "head_addition_names_base_only" "Cursor Bugbot" "$(field "$result" REVIEWER_REPORT)"
# A head that REMOVES a base reviewer cannot waive it: the base platform is
# still gated, its check run is absent, and the label refuses.
MOCK_HEAD_CONFIG='review:
  on_ready:
    github:
      - bugbot'
MOCK_BASE_CONFIG='review:
  on_ready:
    github:
      - bugbot
      - ronda'
MOCK_CHECK_RUNS="$_bugbot_ok"
result="$(run_helper_no_local_config)"
run_test "head_removal_cannot_waive_base_reviewer_reason" "reviewer-check-absent" "$(field "$result" REASON)"
run_test "head_removal_cannot_waive_base_reviewer_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
MOCK_HEAD_CONFIG=''
MOCK_BASE_CONFIG=''
MOCK_CHECK_RUNS="$_bugbot_ok"

# Finding 3 (P2): no label removal on post-apply escalation. Only the
# head-mismatch path removed the label after applying; every other
# post-mutation escalation path left an unverified readiness label attached.
# Case 1: the post-apply `pr view` itself fails after `--add-label`
# succeeded.
MOCK_POST_VIEW_EXIT=1
result="$(run_helper)"
MOCK_POST_VIEW_EXIT=0
run_test "post_view_failure_removes_label" "1" "$(grep -c -- '--remove-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "post_view_failure_still_escalates_exit" "2" "${result%%|*}"
run_test "post_view_failure_reason" "label-verify-failed" "$(field "$result" REASON)"
# Case 2: a label the API silently discards (`label-not-applied`) must also
# attempt removal, not escalate leaving whatever partial state exists.
MOCK_DROP_LABEL=1
result="$(run_helper)"
MOCK_DROP_LABEL=0
run_test "label_not_applied_attempts_removal" "1" "$(grep -c -- '--remove-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "label_not_applied_still_escalates_exit" "2" "${result%%|*}"
run_test "label_not_applied_reason" "label-not-applied" "$(field "$result" REASON)"

echo ""
echo "$pass passed, $fail failed"

if [ "$fail" -ne 0 ]; then
  exit 1
fi