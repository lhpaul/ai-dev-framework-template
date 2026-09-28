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
pr_default='{"headRefOid":"aaaa111000000000000","headRefName":"fix/1408-demo","labels":[],"statusCheckRollup":[]}'
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
    # landing between the state read and the label mutation.
    if [ -n "${MOCK_REVALIDATE_HEAD:-}" ]; then
      printf '%s\n' "$MOCK_REVALIDATE_HEAD"
    else
      emit "${MOCK_PR_JSON:-$pr_default}"
    fi
    exit 0
    ;;
  *"pr view"*"--json labels,headRefOid"*)
    # Post-apply verification. MOCK_POST_APPLY_HEAD simulates a push landing
    # during the mutation itself.
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
  *"pr view"*)
    emit "${MOCK_PR_JSON:-$pr_default}"
    exit 0
    ;;
  *"/check-runs"*)
    [ "${MOCK_CHECK_RUNS_EXIT:-0}" = "0" ] || exit 1
    # The helper fetches with `--paginate --slurp`, so gh returns an array of
    # pages. MOCK_CHECK_RUNS may carry several comma-separated page objects.
    emit "[${MOCK_CHECK_RUNS:-$check_runs_default}]"
    exit 0
    ;;
  *"/pulls/"*"/comments"*)
    emit "[${MOCK_COMMENTS:-$empty_array}]"
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
_BRANCH='fix/1408-demo'
_LABEL_LOG="$TMP_ROOT/gh-calls.log"
_LABEL_STATE="$TMP_ROOT/label-state"

# run_helper — prints "<exit_code>|<stdout>". Payloads come from the MOCK_*
# variables the caller set; a `${VAR:-{...}}` default here would not survive
# parameter expansion, so the fallbacks are plain names.
run_helper() {
  local default_labels='{"labels":[]}'
  local label="${MOCK_LABEL:-ready-for-human-review}"
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
    MOCK_ISSUE_COMMENTS="${MOCK_ISSUE_COMMENTS:-[]}" \
    MOCK_REVALIDATE_HEAD="${MOCK_REVALIDATE_HEAD:-}" \
    MOCK_POST_APPLY_HEAD="${MOCK_POST_APPLY_HEAD:-}" \
    MOCK_DROP_LABEL="${MOCK_DROP_LABEL:-0}" \
    MOCK_HEAD_CONFIG="${MOCK_HEAD_CONFIG:-}" \
    MOCK_HEAD_CONFIG_EXIT="${MOCK_HEAD_CONFIG_EXIT:-0}" \
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

_empty_rollup='{"headRefOid":"'"$HEAD"'","headRefName":"'"$_BRANCH"'","labels":[],"statusCheckRollup":[]}'
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
  set +e
  out="$(
    PATH="$_BIN:$PATH" \
    MOCK_GH_LOG="$_LABEL_LOG" \
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
echo "$pass passed, $fail failed"

if [ "$fail" -ne 0 ]; then
  exit 1
fi