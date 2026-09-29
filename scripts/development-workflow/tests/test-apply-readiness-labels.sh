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
  *"api user"*)
    # Round 18 (PRRT_kwDORWAxaM6m36Wn): the invoker's own login — the login
    # pr-review-loop.sh posts the summary comment under (gh pr comment /
    # gh api --method PATCH via the same token). The ledger trust filter
    # accepts a comment authored by this login. Cached per run so several
    # `gh api user` calls do not consume awk's global state; MOCK_GH_USER
    # overrides it (default: the test's operator fixture login).
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    _uc="${MOCK_TMP_ROOT:-${TMP_ROOT:-/tmp}}/gh-user.cache"
    # The helper calls `gh api user --jq '.login // ""'`: emit the bare
    # login, as gh does once --jq is applied.
    [ -s "$_uc" ] && { cat "$_uc"; exit 0; }
    printf '%s\n' "${MOCK_GH_USER:-loop-runner}" >"$_uc" 2>/dev/null || true
    cat "$_uc" 2>/dev/null || printf '%s\n' 'loop-runner'
    exit 0
    ;;
  *"pr edit"*)
    printf '%s\n' "$*" >>"${MOCK_GH_LOG:?}"
    # Also logged to the shared call log so ordering assertions can prove the
    # mutation's position relative to every other API call (PR #1818 finding
    # 2, round 9).
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
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
    if printf '%s\n' "$*" | grep -q -- "--remove-label"; then
      exit "${MOCK_REMOVE_LABEL_EXIT:-0}"
    fi
    exit "${MOCK_GH_EDIT_EXIT:-0}"
    ;;
  *"pr view"*"--json headRefOid --jq"*)
    # Pre-apply head revalidation — after round 9 there is exactly ONE
    # re-fetch, the final pre-mutation head check (the last API call before
    # `pr edit`). MOCK_FINAL_REVALIDATE_HEAD simulates a push landing during
    # the final-block revalidations/rescans; MOCK_REVALIDATE_HEAD serves on
    # the same call (kept as an alias for the older tests).
    # Logged to a separate call log (not MOCK_GH_LOG, which counts `pr edit`
    # calls only) so the later arms can tell the revalidation fetches from the
    # first.
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    if [ -n "${MOCK_FINAL_REVALIDATE_HEAD:-}" ]; then
      printf '%s\n' "$MOCK_FINAL_REVALIDATE_HEAD"
    elif [ -n "${MOCK_REVALIDATE_HEAD:-}" ]; then
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
    # MOCK_PR_JSON_EXIT fails the initial state read itself (PR #1818
    # finding 1, round 9): an unavailable PR read escalates
    # pr-state-unavailable BEFORE the label-presence capture, so no removal
    # must be attempted on that path.
    [ "${MOCK_PR_JSON_EXIT:-0}" = "0" ] || exit 1
    # First fetch (state read) vs the final-block CI re-read: from the SECOND
    # full-state fetch on, MOCK_REVALIDATE_PR_JSON (if set) replaces the
    # payload — it simulates a CI check re-triggered on the same head after
    # the verdicts were read (PR #1818 findings 2 and 3, rounds 5 and 9: the
    # switch is keyed on the fetch count, not on the head-revalidate call
    # having run, because the reviewer rescan now precedes the CI re-read).
    # MOCK_LATE_CI_PR_JSON (PR #1818 finding 3, round 9) additionally replaces
    # the payload only once the reviewer finding rescan has run (the SECOND
    # comments fetch: main-gate scan, final-block revalidation rescan) — it
    # simulates a CI rerun to pending/failure DURING the rescan window,
    # which a CI read taken before the rescan never sees.
    _s_calls="$(grep -c -- '--json headRefOid,headRefName,baseRefOid,labels,statusCheckRollup' "${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true)"
    _c2="$(grep -c -- 'pulls/42/comments' "${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true)"
    if [ -n "${MOCK_LATE_CI_PR_JSON:-}" ] && [ "${_c2:-0}" -ge 2 ]; then
      emit "$MOCK_LATE_CI_PR_JSON"
    elif [ "${_s_calls:-0}" -ge 1 ] && [ -n "${MOCK_REVALIDATE_PR_JSON:-}" ]; then
      emit "$MOCK_REVALIDATE_PR_JSON"
    else
      emit "${MOCK_PR_JSON:-$pr_default}"
    fi
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    exit 0
    ;;
  *"actions/runs"*)
    # Round 16 (thread PRRT_kwDORWAxaM6m2OtD): Claude Code Action completion
    # evidence — the workflow_dispatch runs list. MOCK_WORKFLOW_RUNS carries
    # the workflow_runs array (empty for "no run").
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    emit "[{\"total_count\":1,\"workflow_runs\":[${MOCK_WORKFLOW_RUNS:-}]}]"
    exit 0
    ;;
  *"runs/"*"/logs"*)
    # Round 17 (PRRT_kwDORWAxaM6m260z): run-log positive-execution check —
    # MOCK_RUN_LOG_EXIT=1 fails the fetch (no positive evidence); an empty
    # MOCK_RUN_LOG is a no-op log (grep matches nothing → refuse).
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    [ "${MOCK_RUN_LOG_EXIT:-0}" = "0" ] || exit 1
    printf '%s\n' "${MOCK_RUN_LOG:-}"
    exit 0
    ;;
  *"commits/"*"--jq"*)
    # Round 17 (PRRT_kwDORWAxaM6m2607): head push time for the greptile
    # cycle binding — `gh api repos/<r>/commits/<sha> --jq .commit.committer.date`.
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    emit "${MOCK_HEAD_COMMIT_JSON:-{\"commit\":{\"committer\":{\"date\":\"2026-01-05T00:00:00Z\"}}}}"
    exit 0
    ;;
  *"reviewThreads"*)
    # Round 27 (PRRT_kwDORWAxaM6m7SZu): unresolved bot review threads.
    # MOCK_REVIEW_THREADS carries the thread nodes array (default none);
    # MOCK_REVIEW_THREADS_EXIT=1 fails the read. Emitted as a slurped page
    # array, the shape --paginate --slurp yields.
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    [ "${MOCK_REVIEW_THREADS_EXIT:-0}" = "0" ] || exit 1
    printf '%s\n' "[{\"data\":{\"repository\":{\"pullRequest\":{\"reviewThreads\":{\"nodes\":${MOCK_REVIEW_THREADS:-[]}}}}}}]"
    exit 0
    ;;
  *"api graphql"*)
    # Round 18 (PRRT_kwDORWAxaM6m36Wu): greptile's push-observation binding —
    # the PR timeline (PullRequestCommit / IssueComment nodes in server
    # order). MOCK_PR_TIMELINE carries the timelineItems nodes array; the
    # stub applies the caller's --jq filter itself (emit would re-apply it
    # to the already-filtered nodes).
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    [ "${MOCK_PR_TIMELINE_EXIT:-0}" = "0" ] || exit 1
    # Round 19 (PRRT_kwDORWAxaM6m5slK): the helper now paginates (--paginate
    # --slurp), so the stub emits an ARRAY OF PAGES. MOCK_PR_TIMELINE_PAGE2,
    # when set, is a second page's nodes (the head commit can sit on page 1
    # with the trigger only on page 2).
    if [ -n "${MOCK_PR_TIMELINE_PAGE2:-}" ]; then
      printf '%s\n' "[{\"data\":{\"repository\":{\"pullRequest\":{\"timelineItems\":{\"nodes\":${MOCK_PR_TIMELINE:-[]}}}}}},{\"data\":{\"repository\":{\"pullRequest\":{\"timelineItems\":{\"nodes\":${MOCK_PR_TIMELINE_PAGE2}}}}}}]"
    else
      printf '%s\n' "[{\"data\":{\"repository\":{\"pullRequest\":{\"timelineItems\":{\"nodes\":${MOCK_PR_TIMELINE:-[]}}}}}}]"
    fi
    exit 0
    ;;
  *"collaborators/"*"/permission"*)
    # Round 19 (PRRT_kwDORWAxaM6m5slC): repository-permission lookup for the
    # ledger author trust check. MOCK_PERMS is a space-separated list of
    # login=permission pairs; an unlisted login has no access (exit 1, as
    # the API 404s for a non-collaborator).
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    _pl="$(printf '%s' "$*" | sed -n 's#.*collaborators/\([^/]*\)/permission.*#\1#p')"
    for _kv in ${MOCK_PERMS:-}; do
      if [ "${_kv%%=*}" = "$_pl" ]; then printf '%s\n' "${_kv#*=}"; exit 0; fi
    done
    exit 1
    ;;
  *"run view"*)
    # Round 17 (PRRT_kwDORWAxaM6m260z): the claude-action run log fetch.
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    [ "${MOCK_RUN_LOG_EXIT:-0}" = "0" ] || exit 1
    printf '%s\n' "${MOCK_RUN_LOG:-}"
    exit 0
    ;;
  *"issues/comments/"*"/reactions"*)
    # Round 15 (thread PRRT_kwDORWAxaM6m1pF_): Greptile completion evidence —
    # a bot +1 on the trigger comment. MOCK_GREPTILE_REACTION carries the
    # reaction list payload (bot login + content "+1").
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    emit "${MOCK_GREPTILE_REACTION:-[]}"
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
    # fetch on — the final-block finding rescan must be able to see findings
    # that did not exist (or were not yet posted) at the first scan (PR #1818
    # finding 2, round 6). MOCK_RERUN_COMMENTS additionally simulates a
    # blocking comment posted by a same-SHA rerun after the first scan (PR
    # #1818 finding 2, rounds 8-9): from the SECOND comments fetch on (the
    # final-block rescan, the last reviewer read before the mutation) the
    # payload gains the rerun's comments, so the rescan still sees them.
    # Decide BEFORE appending to the call log.
    _c_calls="$(grep -c -- 'pulls/42/comments' "${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true)"
    if [ -n "${MOCK_REVALIDATE_COMMENTS:-}" ] \
        && grep -q '/pulls/42/comments' "${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null; then
      emit "[${MOCK_REVALIDATE_COMMENTS}]"
    elif [ "${_c_calls:-0}" -ge 1 ] && [ -n "${MOCK_RERUN_COMMENTS:-}" ]; then
      _base="${MOCK_COMMENTS:-$empty_array}"
      if [ "$_base" = "[]" ]; then
        emit "[[${MOCK_RERUN_COMMENTS}]]"
      else
        emit "[${_base%,}]},${MOCK_RERUN_COMMENTS}]"
      fi
    else
      emit "[${MOCK_COMMENTS:-$empty_array}]"
    fi
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    exit 0
    ;;
  *"/pulls/"*"/reviews"*)
    emit "[${MOCK_REVIEWS:-$empty_array}]"
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    exit 0
    ;;
  *"/issues/"*"/comments"*)
    # Round 18 (threads PRRT_kwDORWAxaM6m36Wn/Wu): the issue-comments read
    # itself is paginated+slurped by the helper, so the stub emits a page
    # array. MOCK_ISSUE_COMMENTS carries ONE page's array; each comment may
    # additionally carry an author_association (the real REST payload does)
    # for the ledger trust filter, and MOCK_LEDGER_ASSEDGE_* fixtures append
    # it here when the raw fixture lacks it.
    emit "[${MOCK_ISSUE_COMMENTS:-$empty_array}]"
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    exit 0
    ;;
  *"repo view"*)
    emit '{"nameWithOwner":"acme/widgets"}'
    exit 0
    ;;
  *"/contents/.ai-dev-workflow.yaml?ref=$MOCK_BASE_SHA"*)
    # Base-branch configuration fetch (PR #1818 finding 1, round 4). A distinct
    # variable so head and base payloads differ in one invocation.
    # `tr -d '\n'`: GNU coreutils base64 wraps at 76 columns by default, which
    # would embed literal newlines in the JSON content string and fail the
    # suite on Linux with base-config-unreadable (PR #1818 finding 3, round 7).
    [ "${MOCK_BASE_CONFIG_EXIT:-0}" = "0" ] || exit 1
    content="$(printf '%s\n' "${MOCK_BASE_CONFIG:-review:
  on_ready:
    github: []}" | base64 | tr -d '\n')"
    emit "{\"content\":\"$content\"}"
    exit 0
    ;;
  *"/contents/.ai-dev-workflow.yaml"*)
    # PR-head configuration fetch (#1408 finding 1). MOCK_HEAD_CONFIG carries
    # the raw YAML body; MOCK_HEAD_CONFIG_EXIT simulates the API failure.
    # Same `tr -d '\n'` wrap guard as the base-config arm above.
    [ "${MOCK_HEAD_CONFIG_EXIT:-0}" = "0" ] || exit 1
    content="$(printf '%s\n' "${MOCK_HEAD_CONFIG:-review:
  on_ready:
    github:
      - bugbot}" | base64 | tr -d '\n')"
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
# order_log — after a run_helper call, prints one line per API call with the
# call class substituted (head / check-runs / comments / reviews / issue-comments /
# rollup-pr / edit), in call order. Ordering invariants (PR #1818 findings 2
# and 3, round 9) are asserted against this: every revalidation/rescan call
# must precede the final headRefOid re-fetch, which must precede `pr edit`.
order_log() {
  sed -e 's|.*--json headRefOid --jq.*|head|' \
      -e 's|.*commits/[^ ]*/check-runs.*|check-runs|' \
      -e 's|.*pulls/42/comments.*|comments|' \
      -e 's|.*pulls/42/reviews.*|reviews|' \
      -e 's|.*issues/42/comments.*|issue-comments|' \
      -e 's|.*--json headRefOid,headRefName,baseRefOid,labels,statusCheckRollup.*|rollup-pr|' \
      -e 's|.*pr edit.*|edit|' \
      "$_CALL_LOG"
}

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
    MOCK_CHECK_RUNS_EXIT="${MOCK_CHECK_RUNS_EXIT:-0}" \
    MOCK_PR_JSON_EXIT="${MOCK_PR_JSON_EXIT:-0}" \
    MOCK_LATE_CI_PR_JSON="${MOCK_LATE_CI_PR_JSON:-}" \
    MOCK_FINAL_REVALIDATE_HEAD="${MOCK_FINAL_REVALIDATE_HEAD:-}" \
    MOCK_RERUN_COMMENTS="${MOCK_RERUN_COMMENTS:-}" \
    MOCK_REMOVE_LABEL_EXIT="${MOCK_REMOVE_LABEL_EXIT:-0}" \
    MOCK_WORKFLOW_RUNS="${MOCK_WORKFLOW_RUNS:-}" \
    MOCK_GH_USER="${MOCK_GH_USER:-}" \
    MOCK_TMP_ROOT="$TMP_ROOT" \
    MOCK_PR_TIMELINE="${MOCK_PR_TIMELINE:-}" \
    MOCK_PR_TIMELINE_PAGE2="${MOCK_PR_TIMELINE_PAGE2:-}" \
    MOCK_REVIEW_THREADS="${MOCK_REVIEW_THREADS:-}" \
    MOCK_REVIEW_THREADS_EXIT="${MOCK_REVIEW_THREADS_EXIT:-0}" \
    MOCK_PERMS="${MOCK_PERMS:-}" \
    MOCK_PR_TIMELINE_EXIT="${MOCK_PR_TIMELINE_EXIT:-0}" \
    PR_AGENT_BOT_LOGIN="${PR_AGENT_BOT_LOGIN:-github-actions[bot]}" \
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

# call_count <pattern> — number of calls in the shared call log matching the
# pattern (pattern must not start with a dash). Used for the round-9
# CI-revalidation repeat and escalate-cleanup assertions (PR #1818 findings 1
# and 3, round 9).
call_count() {
  grep -c "$1" "$_CALL_LOG" 2>/dev/null || printf '0'
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

# PR #1818 F2 round 11 (thread PRRT_kwDORWAxaM6mzC5k): a check run that
# concludes `success` while the reviewer posted blocking inline comments
# (comment-only findings) must still mark the PR `needs-fixes`. The
# per-platform verdict block (~line 647) runs BEFORE
# count_reviewer_blocking_findings accumulates, so the aggregate
# blocking-findings refusal fired with no needs-fixes annotation.
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_COMMENTS='[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","in_reply_to_id":null,"body":"**High Severity** leak in the reject path","created_at":"2026-01-02T00:00:00Z"}]'
MOCK_REVIEWS='[]'
result="$(run_helper)"
run_test "comment_only_findings_exit" "1" "${result%%|*}"
run_test "comment_only_findings_reason" "blocking-findings" "$(field "$result" REASON)"
run_test "comment_only_findings_count" "1" "$(field "$result" BLOCKING_FINDING_COUNT)"
run_test "comment_only_findings_marked_needs_fixes" "1" "$(grep -c 'add-label needs-fixes' "$_LABEL_LOG" || true)"
run_test "comment_only_findings_no_readiness_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
MOCK_COMMENTS='[]'

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
# Round 21 (PRRT_kwDORWAxaM6m6dJ3): a newly queued rerun has no started_at /
# completed_at; it is the NEWEST run and must beat the older completed success.
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"success","started_at":"2026-02-01T00:00:00Z"},{"name":"Cursor Bugbot","status":"queued","conclusion":null,"started_at":null,"completed_at":null}]}'
result="$(run_helper)"
run_test "queued_rerun_beats_older_success_reason" "reviewer-check-not-completed" "$(field "$result" REASON)"

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
# `gh pr edit ... --add-label "ready-for-*"`. The release protocol was the one
# documented exemption (release PRs have no reviewer check run), but PR #1818
# round 10 removed it: the helper classifies release/* heads as
# non-implementation and skips the reviewer leg on its own, so §7.3 routes
# through the helper like every other surface.
for surface in \
  docs/workflow/development-workflow/protocols/03-implement-development-protocol.md \
  docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md \
  docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md \
  .claude/commands/sync-template.md \
  .claude/skills/sync-template.md \
  .cursor/commands/sync-template.md
do
  bare="$(grep -c 'add-label "ready-for-' "$REPO_ROOT/$surface" || true)"
  run_test "$surface has no bare ready-* apply" "0" "$bare"
done

release_surface="docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md"
readiness92_surface="docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md"
run_test "05 routes the regression label through the helper" "1" \
  "$([ "$(grep -c 'apply-readiness-labels.sh' "$REPO_ROOT/$release_surface" || true)" -ge 1 ] && echo 1 || echo 0)"
run_test "05 release exemption removed" "0" \
  "$(grep -c 'documented exemption from helper-gated readiness labels' "$REPO_ROOT/$release_surface" || true)"

# PR #1818 F1 round 11 (thread PRRT_kwDORWAxaM6mzC5e): §7.4's CI-loop `green`
# row must route the release `ready-for-human-review` through the helper, not
# point at protocol 92's direct apply — a direct apply bypasses the helper's
# live CI/head revalidation exactly the way the §7.3 direct apply did before
# round 10.
_p05_green="$(awk '/^### 7.4 CI loop/{f=1} f && /^### 7.5 /{exit} f{print}' "$REPO_ROOT/$release_surface")"
run_test "05_ci_green_row_uses_readiness_helper" "1" "$(printf '%s\n' "$_p05_green" | grep -c 'apply-readiness-labels.sh --pr <pr_number> --label ready-for-human-review' || true)"  # workflow-shell-guard: allow SH001 - grep -c exits 1 on zero matches; the assertion on this line decides pass/fail.
run_test "05_ci_green_row_no_direct_apply_instruction" "0" \
  "$(printf '%s\n' "$_p05_green" | grep -c 'Apply `ready-for-human-review` per' || true)"
run_test "05_ci_green_row_no_direct_gh_edit" "0" "$(printf '%s\n' "$_p05_green" | grep -c 'gh pr edit --add-label ready-for-human-review' || true)"  # workflow-shell-guard: allow SH001 - grep -c exits 1 on zero matches; the assertion on this line decides pass/fail.
# The red row's `needs-fixes` apply is a plain annotation (not a readiness
# label the merge gates consume), so it keeps its direct form — the
# consistency assertion locks that it stays an annotation, never a
# ready-* label.
run_test "05_ci_red_row_never_applies_ready_label" "0" \
  "$(printf '%s\n' "$_p05_green" | grep -c 'Apply `ready-for' || true)"
unset _p05_green

# PR #1818 codex-github round 12 (thread PRRT_kwDORWAxaM6mzsYm): the two
# remaining readiness producers must route through the helper too.
# (a) pr-policy.yml's apply_regression_policy_after_clean_summary applied
#     ready-for-regression via a direct `gh pr edit --add-label "$LABEL_NAME"`,
#     bypassing the live reviewer/CI/head validation the helper enforces —
#     the comment-echoed summary evidence is exactly the spoofable surface
#     the gate exists for.
# (b) Protocol 92's "Work Item Runner advances a draft PR" steps 6/8 and the
#     "Human requests changes" re-add step instructed standalone loop
#     agents/skills to hand-apply both readiness labels.
readiness_policy_surface=".github/workflows/pr-policy.yml"
_p_policy="$(awk '/apply_regression_policy_after_clean_summary\(\) \{/{f=1} f{print} f && /^[[:space:]]*}$/{exit}' "$REPO_ROOT/$readiness_policy_surface")"
run_test "pr_policy_applies_regression_label_via_helper" "1" \
  "$([ "$(printf '%s\n' "$_p_policy" | grep -c 'apply-readiness-labels.sh' || true)" -ge 1 ] && echo 1 || echo 0)"
run_test "pr_policy_no_direct_regression_label_add" "0" \
  "$(printf '%s\n' "$_p_policy" | grep -- '--add-label "\$LABEL_NAME"' | grep -cv '^[[:space:]]*#' || true)"
run_test "pr_policy_apply_block_only_label_remove_is_direct" "0" \
  "$(printf '%s\n' "$_p_policy" | grep -- '--remove-label "\$LABEL_NAME"' | grep -cv '^[[:space:]]*#' || true)"
run_test "pr_policy_helper_present_repo_route" "1" \
  "$([ "$(grep -c 'apply-readiness-labels.sh' "$REPO_ROOT/$readiness_policy_surface" || true)" -ge 2 ] && echo 1 || echo 0)"
unset _p_policy

# Protocol 92 standard-workflow steps 6 and 8: both readiness labels go
# through the helper; a direct apply instruction is forbidden. The
# `needs-fixes` annotation stays a plain label edit (not a readiness label),
# so those steps keep their direct form.
_p92_std="$(awk '/^### Work Item Runner advances a draft PR/{f=1} f{print} f && /^### Human requests changes/{exit}' "$REPO_ROOT/$readiness92_surface")"
run_test "protocol92_step6_uses_readiness_helper" "1" \
  "$([ "$(printf '%s\n' "$_p92_std" | grep -c 'apply-readiness-labels.sh --pr <pr-number> --label ready-for-regression' || true)" -ge 1 ] && echo 1 || echo 0)"
run_test "protocol92_step8_uses_readiness_helper" "1" \
  "$([ "$(printf '%s\n' "$_p92_std" | grep -c 'apply-readiness-labels.sh --pr <pr-number> --label ready-for-human-review' || true)" -ge 1 ] && echo 1 || echo 0)"
run_test "protocol92_standard_workflow_no_direct_apply_instruction" "0" \
  "$(printf '%s\n' "$_p92_std" | grep -c 'apply `ready-for-\(regression\|human-review\)` label' || true)"
# Protocol 92 human-changes re-add step (step 6 of that list).
_p92_human="$(awk '/^### Human requests changes/{f=1} f{print} f && /^## Recommended Automation/{exit}' "$REPO_ROOT/$readiness92_surface")"
run_test "protocol92_human_changes_readd_uses_helper" "1" \
  "$([ "$(printf '%s\n' "$_p92_human" | grep -c 'apply-readiness-labels.sh --pr <pr-number> --label ready-for-human-review' || true)" -ge 1 ] && echo 1 || echo 0)"
run_test "protocol92_human_changes_no_direct_readd" "0" \
  "$(printf '%s\n' "$_p92_human" | grep -c '[^e-]add `ready-for-human-review`' || true)"
unset _p92_std _p92_human

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

# Finding 1 (P1), superseded semantics (round 14, thread
# PRRT_kwDORWAxaM6m1Dec): codex-github is a DOCUMENTED comment-only
# ready-phase platform, so the round-era reviewer-check-name-unresolved
# refusal became a permanent deadlock. It now gates on the bot's PR review
# for the head: with no review posted the helper still refuses fail-closed —
# reviewer-check-absent, never a silent pass.
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
run_test "unresolved_platform_reason" "reviewer-check-absent" "$(printf '%s\n' "$out" | sed -n 's/^REASON=//p' | tail -1)"
run_test "unresolved_platform_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "unresolved_platform_names_platform" "codex-github:review" "$(printf '%s\n' "$out" | sed -n 's/^REVIEWER_REPORT=//p' | tail -1)"

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
    WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="${MOCK_LOCAL_OVERRIDE_ROOT:-}" \
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
    MOCK_CHECK_RUNS_EXIT="${MOCK_CHECK_RUNS_EXIT:-0}" \
    MOCK_PR_JSON_EXIT="${MOCK_PR_JSON_EXIT:-0}" \
    MOCK_LATE_CI_PR_JSON="${MOCK_LATE_CI_PR_JSON:-}" \
    MOCK_FINAL_REVALIDATE_HEAD="${MOCK_FINAL_REVALIDATE_HEAD:-}" \
    MOCK_RERUN_COMMENTS="${MOCK_RERUN_COMMENTS:-}" \
    MOCK_REMOVE_LABEL_EXIT="${MOCK_REMOVE_LABEL_EXIT:-0}" \
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
# Round 27 (PRRT_kwDORWAxaM6m7SZu): the same stale comment's review THREAD,
# still unresolved, keeps blocking (canonical loop audits all bot threads);
# once resolved it no longer does; an unreadable thread surface escalates.
MOCK_REVIEW_THREADS='[{"isResolved":false,"comments":{"nodes":[{"author":{"login":"cursor"}}]}}]'
result="$(run_helper)"
run_test "stale_comment_unresolved_thread_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
MOCK_REVIEW_THREADS='[{"isResolved":true,"comments":{"nodes":[{"author":{"login":"cursor"}}]}}]'
result="$(run_helper)"
run_test "stale_comment_resolved_thread_labels_result" "labeled" "$(field "$result" RESULT)"
MOCK_REVIEW_THREADS='[{"isResolved":false,"comments":{"nodes":[{"author":{"login":"some-human"}}]}}]'
result="$(run_helper)"
run_test "unresolved_non_bot_thread_ignored_result" "labeled" "$(field "$result" RESULT)"
MOCK_REVIEW_THREADS='[{"isResolved":false,"isOutdated":true,"comments":{"nodes":[{"author":{"login":"cursor"},"body":"old"}]}},{"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"cursor"},"body":"✅ Addressed in abc"}]}}]'
result="$(run_helper)"
run_test "outdated_and_addressed_threads_do_not_block_result" "labeled" "$(field "$result" RESULT)"
MOCK_REVIEW_THREADS_EXIT=1
result="$(run_helper)"
run_test "thread_fetch_failure_escalates_reason" "review-thread-fetch-failed" "$(field "$result" REASON)"
MOCK_REVIEW_THREADS_EXIT=0
MOCK_REVIEW_THREADS=''
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
echo "=== Area 12: PR #1818 Codex findings, round 7 ==="

# Reset to the clean default before the planted cases.
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[]'
MOCK_HEAD_CONFIG=''
MOCK_BASE_CONFIG=''
MOCK_LOCAL_OVERRIDE_ROOT=''

# Finding 1 (P1): pr-review-loop.sh's _check_release_pr_guard skips the
# reviewer loop for hotfix/* head branches exactly as it does for release/*,
# so no ready-phase reviewer check run can ever exist on a hotfix. Requiring
# one permanently refused both readiness labels reviewer-check-absent.
# Planted failing case: a hotfix branch with the empty check-run set must NOT
# refuse on the reviewer leg (it still runs the CI leg, so a failing check
# still refuses — asserted right after).
MOCK_PR_JSON='{"headRefOid":"'"$HEAD"'","headRefName":"hotfix/v9.9.9","baseRefOid":"'"$BASE_SHA"'","labels":[],"statusCheckRollup":[]}'
MOCK_CHECK_RUNS='{"check_runs":[]}'
result="$(run_helper)"
run_test "hotfix_branch_not_reviewer_gated_exit" "0" "${result%%|*}"
run_test "hotfix_branch_not_reviewer_gated_result" "labeled" "$(field "$result" RESULT)"
run_test "hotfix_branch_not_reviewer_gated_report" "none" "$(field "$result" REVIEWER_REPORT)"
# The CI leg still applies on hotfix branches (the same handling release
# branches get): a failing non-reviewer check refuses.
MOCK_PR_JSON='{"headRefOid":"'"$HEAD"'","headRefName":"hotfix/v9.9.9","baseRefOid":"'"$BASE_SHA"'","labels":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","workflowName":"ShellCheck","status":"COMPLETED","conclusion":"FAILURE"}]}'
result="$(run_helper)"
run_test "hotfix_branch_ci_leg_still_applies_reason" "ci-failing" "$(field "$result" REASON)"
# backport/hotfix/* is an implementation branch and stays reviewer-gated.
MOCK_PR_JSON='{"headRefOid":"'"$HEAD"'","headRefName":"backport/hotfix/v9.9.9","baseRefOid":"'"$BASE_SHA"'","labels":[],"statusCheckRollup":[]}'
result="$(run_helper)"
run_test "backport_hotfix_still_reviewer_gated_reason" "reviewer-check-absent" "$(field "$result" REASON)"
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS="$_bugbot_ok"

# Finding 2 (P1): the loop resolves the base snapshot's review policy with
# WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 (pr-review-loop.sh ~12423-12449), so
# a local .ai-dev-workflow.local.yaml declaring review.on_ready.github
# REPLACES the shared list. This helper previously parsed the base snapshot
# without overrides, so a local ronda-over-bugbot override made it wait for a
# Bugbot check the loop never dispatched. Planted failing case: the override
# root declares ronda; the shared base config declares bugbot; the check-run
# payload has a clean Ronda run and NO Bugbot run. Pre-fix, the helper
# resolved bugbot and refused reviewer-check-absent; the fixed helper must
# resolve the overridden ronda policy and label.
mkdir -p "$TMP_ROOT/override-root"
cat > "$TMP_ROOT/override-root/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  on_ready:
    github:
      - ronda
YAML
MOCK_LOCAL_OVERRIDE_ROOT="$TMP_ROOT/override-root"
MOCK_HEAD_CONFIG='review:
  on_ready:
    github:
      - ronda'
MOCK_BASE_CONFIG='review:
  on_ready:
    github:
      - bugbot'
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Ronda review","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z"}]}'
result="$(run_helper_no_local_config)"
run_test "local_override_replaces_base_policy_exit" "0" "${result%%|*}"
run_test "local_override_replaces_base_policy_result" "labeled" "$(field "$result" RESULT)"
run_test "local_override_replaces_base_policy_names" "Ronda review" "$(field "$result" REVIEWER_REPORT)"
# Override ABSENT (the worktree case, #1817): fall back to the shared base
# policy, never fail — the loop's own behavior in a worktree.
MOCK_LOCAL_OVERRIDE_ROOT=""
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z"}]}'
result="$(run_helper_no_local_config)"
run_test "absent_override_falls_back_to_shared_base_exit" "0" "${result%%|*}"
run_test "absent_override_falls_back_to_shared_base_names" "Cursor Bugbot" "$(field "$result" REVIEWER_REPORT)"
MOCK_HEAD_CONFIG=''
MOCK_BASE_CONFIG=''
MOCK_CHECK_RUNS="$_bugbot_ok"
rm -rf "$TMP_ROOT/override-root"

# Finding 3 (P1): GNU coreutils base64 wraps at 76 columns by default; the
# fixture encoders embed the result in a JSON `content` string, so wrapping
# yields invalid JSON and fails 4 cases on Linux with
# ready-config-unreadable / base-config-unreadable. Cannot reproduce GNU
# locally (BSD base64 does not wrap); verify by reasoning + the one-line
# invariant the encoders now guarantee: base64 | tr -d '\n' emits exactly one
# line (wc -l == 1), and the longer MOCK_HEAD_CONFIG default survives a
# round-trip decode.
_enc="$(printf '%s\n' "review:
  on_ready:
    github:
      - bugbot" | base64 | tr -d '\n')"
run_test "base64_encoder_single_line" "1" "$(printf '%s\n' "$_enc" | wc -l | tr -d ' ')"
_dec="$(printf '%s\n' "$_enc" | base64 -d 2>/dev/null || true)"
run_test "base64_encoder_round_trips" "1" "$(printf '%s\n' "$_dec" | grep -c 'bugbot' || true)"
unset _enc _dec

echo ""
echo "=== Area 13: PR #1818 Codex findings, round 8 ==="

# Reset to the clean default before the planted cases.
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[]'
MOCK_HEAD_CONFIG=''
MOCK_BASE_CONFIG=''
MOCK_LOCAL_OVERRIDE_ROOT=''
MOCK_FINAL_REVALIDATE_HEAD=''
MOCK_RERUN_COMMENTS=''
MOCK_REVALIDATE_CHECK_RUNS=''
MOCK_REVALIDATE_PR_JSON=''
MOCK_REVALIDATE_COMMENTS=''
MOCK_POST_VIEW_EXIT=0
MOCK_POST_APPLY_HEAD=''
MOCK_REVALIDATE_HEAD=''
MOCK_DROP_LABEL=0

# Finding 1 (P1): the helper rerun on a PR that ALREADY carries the requested
# label must remove that label on any pre-apply refusal — a refusal verdict
# while a stale readiness label stays attached is exactly what the delegated
# and batch merge gates consume as an all-clear. Planted failing case: the PR
# already has the label and the reviewer check run is absent.
_label_present_pr='{"headRefOid":"'"$HEAD"'","headRefName":"'"$_BRANCH"'","baseRefOid":"'"$BASE_SHA"'","labels":[{"name":"ready-for-human-review"}],"statusCheckRollup":[]}'
MOCK_PR_JSON="$_label_present_pr"
MOCK_CHECK_RUNS='{"check_runs":[]}'
result="$(run_helper)"
run_test "preapply_refusal_removes_stale_label" "1" "$(grep -c -- '--remove-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "preapply_refusal_still_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
run_test "preapply_refusal_exit" "1" "${result%%|*}"
run_test "preapply_refusal_no_add" "0" "$(grep -c -- '--add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# Removal applies to every pre-apply refusal path, not only the reviewer leg:
# a pre-existing label plus a failing CI check removes it as well.
MOCK_PR_JSON='{"headRefOid":"'"$HEAD"'","headRefName":"'"$_BRANCH"'","baseRefOid":"'"$BASE_SHA"'","labels":[{"name":"ready-for-human-review"}],"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","workflowName":"ShellCheck","status":"COMPLETED","conclusion":"FAILURE"}]}'
MOCK_CHECK_RUNS="$_bugbot_ok"
result="$(run_helper)"
MOCK_CHECK_RUNS='{"check_runs":[]}'
run_test "ci_refusal_removes_stale_label" "1" "$(grep -c -- '--remove-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "ci_refusal_reason" "ci-failing" "$(field "$result" REASON)"
# The head-drift refusal (label already present, head moved) removes too.
MOCK_PR_JSON="$_label_present_pr"
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_REVALIDATE_HEAD='bbbb222000000000000'
result="$(run_helper)"
MOCK_REVALIDATE_HEAD=''
run_test "head_drift_refusal_removes_stale_label" "1" "$(grep -c -- '--remove-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "head_drift_refusal_reason" "head-changed-before-apply" "$(field "$result" REASON)"
# And the revalidation-state refusal.
MOCK_REVALIDATE_CHECK_RUNS="$_bugbot_running"
result="$(run_helper)"
MOCK_REVALIDATE_CHECK_RUNS=''
run_test "revalidation_refusal_removes_stale_label" "1" "$(grep -c -- '--remove-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "revalidation_refusal_reason" "reviewer-state-changed" "$(field "$result" REASON)"
# NO removal when the label was NOT already present (the pre-fix contract, and
# the negative guard for the fix: refusal on a label-less PR stays label-less).
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS='{"check_runs":[]}'
result="$(run_helper)"
run_test "refusal_without_existing_label_no_removal" "0" "$(grep -c -- '--remove-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "refusal_without_existing_label_reason" "reviewer-check-absent" "$(field "$result" REASON)"
# Clean run on a PR that already carries the label: labels, does NOT remove.
MOCK_PR_JSON="$_label_present_pr"
MOCK_CHECK_RUNS="$_bugbot_ok"
result="$(run_helper)"
run_test "clean_run_existing_label_no_removal" "0" "$(grep -c -- '--remove-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "clean_run_existing_label_labeled" "labeled" "$(field "$result" RESULT)"
# Removal failure (API rejects --remove-label) still refuses, and still adds
# nothing: WARN-and-refuse, the best-effort contract.
_pre_remove_fail_pr='{"headRefOid":"'"$HEAD"'","headRefName":"'"$_BRANCH"'","baseRefOid":"'"$BASE_SHA"'","labels":[{"name":"ready-for-human-review"}],"statusCheckRollup":[]}'
MOCK_PR_JSON="$_pre_remove_fail_pr"
MOCK_CHECK_RUNS='{"check_runs":[]}'
MOCK_REMOVE_LABEL_EXIT=1
result="$(run_helper)"
MOCK_REMOVE_LABEL_EXIT=0
run_test "removal_failure_still_refuses" "reviewer-check-absent" "$(field "$result" REASON)"
run_test "removal_failure_no_add" "0" "$(grep -c -- '--add-label ready-for-human-review' "$_LABEL_LOG" || true)"
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS="$_bugbot_ok"

# Finding 2 (P1): the head must be re-checked immediately BEFORE the label
# mutation — AFTER the revalidation rescan/CI revalidation, whose API calls
# are exactly the window a push can land in. Planted failing case: the first
# revalidate call (before revalidation) reports the same head, the second
# (post-revalidation, pre-mutation) reports a NEW head. Pre-fix code had only
# the first check and applied the label on the new unreviewed head.
MOCK_FINAL_REVALIDATE_HEAD='eeee555000000000000'
result="$(run_helper)"
MOCK_FINAL_REVALIDATE_HEAD=''
run_test "head_drift_after_revalidation_refuses_reason" "head-changed-before-apply" "$(field "$result" REASON)"
run_test "head_drift_after_revalidation_exit" "1" "${result%%|*}"
run_test "head_drift_after_revalidation_no_add" "0" "$(grep -c -- '--add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# Same head on both revalidate calls: labels (regression guard).
result="$(run_helper)"
run_test "stable_head_still_labels" "labeled" "$(field "$result" RESULT)"

# Finding 3 (P2): notice and finding time-boundary filters must be INCLUSIVE
# (>=). A notice or finding created in the SAME second as the check run's
# started_at is part of that run's output; a strict > drops it and reads the
# non-review as clean. Planted failing case: the usage-limit issue comment's
# created_at EQUALS the neutral check run's started_at.
MOCK_CHECK_RUNS="$_bugbot_neutral"
MOCK_ISSUE_COMMENTS='[{"user":{"login":"cursor[bot]"},"created_at":"2026-01-01T00:00:00Z","body":"<h3>Bugbot couldn'\''t run - usage limit reached</h3>"}]'
result="$(run_helper)"
run_test "same_second_notice_refuses_reason" "reviewer-unavailable" "$(field "$result" REASON)"
run_test "same_second_notice_exit" "1" "${result%%|*}"
MOCK_ISSUE_COMMENTS='[]'
MOCK_CHECK_RUNS="$_bugbot_ok"
# Same boundary on the inline-comment finding surface: a blocking comment
# created exactly at started_at blocks.
MOCK_CHECK_RUNS='{"check_runs":[{"name":"Cursor Bugbot","status":"completed","conclusion":"success","started_at":"2026-03-01T00:00:00Z"}]}'
MOCK_COMMENTS='[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","in_reply_to_id":null,"created_at":"2026-03-01T00:00:00Z","body":"**High Severity** same-second finding"}]'
result="$(run_helper)"
run_test "same_second_comment_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
MOCK_COMMENTS='[]'
# Same boundary on the review surface: a CHANGES_REQUESTED review submitted
# exactly at started_at blocks.
MOCK_REVIEWS='[{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","state":"CHANGES_REQUESTED","body":"","submitted_at":"2026-03-01T00:00:00Z"}]'
result="$(run_helper)"
run_test "same_second_review_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
MOCK_REVIEWS='[]'
MOCK_CHECK_RUNS="$_bugbot_ok"

# The rescan-before-head-check is the last reviewer read before `gh pr
# edit`: a same-SHA rerun that posts a blocking comment after the FIRST scan
# (round 9 keeps exactly one rescan, then the head check, then the mutation)
# must still refuse.
MOCK_RERUN_COMMENTS='{"user":{"login":"cursor[bot]"},"commit_id":"'"$HEAD"'","in_reply_to_id":null,"created_at":"2026-01-03T00:00:00Z","body":"**High Severity** posted after the first scan"}'
result="$(run_helper)"
MOCK_RERUN_COMMENTS=''
run_test "late_comment_before_mutation_refuses_reason" "reviewer-state-changed" "$(field "$result" REASON)"
run_test "late_comment_before_mutation_no_add" "0" "$(grep -c -- '--add-label ready-for-human-review' "$_LABEL_LOG" || true)"

echo ""
echo "=== Area 14: PR #1818 Codex findings, round 9 ==="

# Reset to the clean default before the planted cases.
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[]'
MOCK_REVALIDATE_PR_JSON=''
MOCK_REVALIDATE_COMMENTS=''
MOCK_REVALIDATE_CHECK_RUNS=''
MOCK_FINAL_REVALIDATE_HEAD=''
MOCK_RERUN_COMMENTS=''
MOCK_DROP_LABEL=0

# Finding 1 (P1): escalate() paths left the stale label. A rerun on a PR that
# already carries the requested label and then hits an API/parse failure
# (check-run fetch fails, revalidation-unreadable, config-unreadable, ...)
# exits 2 while the label stays attached — exactly the stale-label
# the merge gates consume. Planted failing case: the label is already present
# and the revalidation check-run fetch fails (revalidation-unreadable).
MOCK_PR_JSON="$_label_present_pr"
MOCK_REVALIDATE_CHECK_RUNS_EXIT=1
result="$(run_helper)"
MOCK_REVALIDATE_CHECK_RUNS_EXIT=0
run_test "escalate_unreadable_removes_stale_label" "1" "$(grep -c -- '--remove-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "escalate_unreadable_reason" "revalidation-unreadable" "$(field "$result" REASON)"
run_test "escalate_unreadable_exit" "2" "${result%%|*}"
# Escalate AFTER the initial state read (check-run fetch failure at round 9's
# final block would be too late to plant; a main-gate fetch failure is the
# same exit path) also removes: the label is present, the first check-runs
# fetch fails.
MOCK_CHECK_RUNS_EXIT=1
result="$(run_helper)"
MOCK_CHECK_RUNS_EXIT=0
run_test "escalate_main_gate_fetch_removes_stale_label" "1" "$(grep -c -- '--remove-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "escalate_main_gate_fetch_reason" "check-run-fetch-failed" "$(field "$result" REASON)"
# Escalate BEFORE the initial presence is captured must NOT attempt removal:
# pr-state-unavailable fires before label_initially_present is computed.
# Planted failing case for the over-removal direction: an unavailable PR read
# with a label-bearing MOCK_LABELS must never remove the label (it was never
# read as present).
MOCK_PR_JSON=''
MOCK_PR_JSON_EXIT=1
result="$(run_helper)"
MOCK_PR_JSON_EXIT=0
MOCK_PR_JSON="$_empty_rollup"
run_test "escalate_before_presence_no_removal" "0" "$(grep -c -- '--remove-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "escalate_before_presence_reason" "pr-state-unavailable" "$(field "$result" REASON)"

# Finding 3 (P1): CI must be re-read AFTER the reviewer rescan, immediately
# before the mutation — a CI rerun to pending/failure during the rescan
# window is missed otherwise, and unlike head drift, post-apply verification
# cannot catch it. The order_log assertions prove the shape: at least two
# rollup reads (main gate + final block), every rescan/comment/review/read
# class's LAST call before the FINAL head call, and the final head call
# immediately before the edit (PR #1818 finding 2, round 9 invariant).
result="$(run_helper)"
run_test "clean_run_ci_revalidation_count" "2" "$(call_count 'json headRefOid,headRefName,baseRefOid,labels,statusCheckRollup')"
run_test "order_final_head_is_last_call_before_edit" "1" "$(
  order_log | awk '
    { lines[NR] = $0 }
    END {
      edit_line = 0; head_line = 0; rollup_last = 0; comments_last = 0; reviews_last = 0
      for (i = NR; i >= 1; i--) {
        if (lines[i] == "edit" && edit_line == 0) edit_line = i
        if (lines[i] == "head" && head_line == 0) head_line = i
        if (lines[i] == "rollup-pr" && rollup_last == 0) rollup_last = i
        if (lines[i] == "comments" && comments_last == 0) comments_last = i
        if (lines[i] == "reviews" && reviews_last == 0) reviews_last = i
      }
      ok = (edit_line == NR) && (head_line == NR - 1) \
           && (rollup_last < head_line) && (comments_last < head_line) \
           && (reviews_last < head_line)
      print ok ? 1 : 0
    }')"
# A CI rerun to pending DURING the rescan window must refuse: the reviewer
# rescan (comments/reviews fetches) runs first, the CI re-read after it sees
# the pending check. MOCK_LATE_CI_PR_JSON surfaces the pending rollup only
# once the final-block rescan has run (third comments fetch), so pre-fix code
# — which read CI before the rescan and never again — labels from the clean
# first read. Planted failing case for PR #1818 finding 3, round 9.
MOCK_LATE_CI_PR_JSON='{"headRefOid":"'"$HEAD"'","headRefName":"'"$_BRANCH"'","labels":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","workflowName":"ShellCheck","status":"IN_PROGRESS","conclusion":null}]}'
result="$(run_helper)"
MOCK_LATE_CI_PR_JSON=''
run_test "ci_rerun_during_rescan_window_refuses_reason" "reviewer-state-changed" "$(field "$result" REASON)"
run_test "ci_rerun_during_rescan_window_no_add" "0" "$(grep -c -- '--add-label ready-for-human-review' "$_LABEL_LOG" || true)"
MOCK_PR_JSON="$_empty_rollup"

echo ""
echo "=== Area 15: PR #1818 codex-github finding, round 14 ==="

# Thread PRRT_kwDORWAxaM6m1Dec: the helper mapped only haystack/bugbot/ronda
# to check-run names and refused every other documented ready-phase platform
# as reviewer-check-name-unresolved. Since rounds 11-13 routed EVERY
# readiness-label producer through this helper, a repository configured with
# e.g. codex-github (this PR's own live case) or coderabbit could never reach
# either readiness label even though pr-review-loop.sh fully supports those
# platforms — the round-era fail-closed default became a permanent deadlock.
# Comment-only platforms (codex-github, coderabbit, ...) publish no check run:
# their "reviewer ran and was clean" verdict is the latest PR review by the
# platform bot for the head SHA. An unknown platform string must still refuse
# reviewer-check-name-unresolved (typo guard).

# Reset to the clean default before the planted cases.
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[]'
MOCK_HEAD_CONFIG=''
MOCK_BASE_CONFIG=''
MOCK_REVALIDATE_PR_JSON=''
MOCK_REVALIDATE_COMMENTS=''
MOCK_REVALIDATE_CHECK_RUNS=''
MOCK_FINAL_REVALIDATE_HEAD=''
MOCK_RERUN_COMMENTS=''
MOCK_DROP_LABEL=0
MOCK_LOCAL_OVERRIDE_ROOT=''

_codex_config="$TMP_ROOT/codex-github-config"
mkdir -p "$_codex_config"
cat > "$_codex_config/workflow.yaml" <<'YAML'
review:
  on_ready:
    github:
      - codex-github
YAML
# A head/base pair both declaring codex-github. Planted failing case 1: a
# clean COMMENTED review by chatgpt-codex-connector[bot] on the head SHA —
# pre-fix the helper refused reviewer-check-name-unresolved before ever
# reading the review surface.
run_helper_platform() {
  local label="${MOCK_LABEL:-ready-for-human-review}"
  : >"$_LABEL_LOG"
  : >"$_LABEL_STATE"
  : >"$_CALL_LOG"
  : >"${TMP_ROOT:-/tmp}/gh-user.cache"
  set +e
  out="$(
    PATH="$_BIN:$PATH" \
    WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="" \
    MOCK_GH_LOG="$_LABEL_LOG" \
    MOCK_CALL_LOG="$_CALL_LOG" \
    MOCK_LABEL_STATE="$_LABEL_STATE" \
    MOCK_PR_JSON="${MOCK_PR_JSON:-}" \
    MOCK_CHECK_RUNS="${MOCK_CHECK_RUNS:-}" \
    MOCK_COMMENTS="${MOCK_COMMENTS:-[]}" \
    MOCK_REVIEWS="${MOCK_REVIEWS:-[]}" \
    MOCK_LABELS='{"labels":[]}' \
    MOCK_ISSUE_COMMENTS="${MOCK_ISSUE_COMMENTS:-[]}" \
    MOCK_REVALIDATE_HEAD="" \
    MOCK_POST_APPLY_HEAD="" \
    MOCK_DROP_LABEL="0" \
    MOCK_HEAD_CONFIG="${MOCK_HEAD_CONFIG:-}" \
    MOCK_HEAD_CONFIG_EXIT="${MOCK_HEAD_CONFIG_EXIT:-0}" \
    MOCK_BASE_SHA="$BASE_SHA" \
    MOCK_BASE_CONFIG="${MOCK_BASE_CONFIG:-}" \
    MOCK_BASE_CONFIG_EXIT="${MOCK_BASE_CONFIG_EXIT:-0}" \
    MOCK_REVALIDATE_CHECK_RUNS="" \
    MOCK_REVALIDATE_PR_JSON="" \
    MOCK_REVALIDATE_COMMENTS="" \
    MOCK_REVALIDATE_CHECK_RUNS_EXIT="0" \
    MOCK_POST_VIEW_EXIT="0" \
    MOCK_CHECK_RUNS_EXIT="0" \
    MOCK_PR_JSON_EXIT="0" \
    MOCK_LATE_CI_PR_JSON="" \
    MOCK_FINAL_REVALIDATE_HEAD="" \
    MOCK_RERUN_COMMENTS="" \
    MOCK_REMOVE_LABEL_EXIT="0" \
    MOCK_GREPTILE_REACTION="${MOCK_GREPTILE_REACTION:-}" \
    MOCK_WORKFLOW_RUNS="${MOCK_WORKFLOW_RUNS:-}" \
    MOCK_RUN_LOG="${MOCK_RUN_LOG:-}" \
    MOCK_RUN_LOG_EXIT="${MOCK_RUN_LOG_EXIT:-0}" \
    MOCK_HEAD_COMMIT_JSON="${MOCK_HEAD_COMMIT_JSON:-}" \
    MOCK_GH_USER="${MOCK_GH_USER:-}" \
    MOCK_TMP_ROOT="$TMP_ROOT" \
    MOCK_PR_TIMELINE="${MOCK_PR_TIMELINE:-}" \
    MOCK_PR_TIMELINE_PAGE2="${MOCK_PR_TIMELINE_PAGE2:-}" \
    MOCK_REVIEW_THREADS="${MOCK_REVIEW_THREADS:-}" \
    MOCK_REVIEW_THREADS_EXIT="${MOCK_REVIEW_THREADS_EXIT:-0}" \
    MOCK_PERMS="${MOCK_PERMS:-}" \
    MOCK_PR_TIMELINE_EXIT="${MOCK_PR_TIMELINE_EXIT:-0}" \
    PR_AGENT_BOT_LOGIN="${PR_AGENT_BOT_LOGIN:-github-actions[bot]}" \
    "$HELPER" --pr 42 --repo acme/widgets --label "$label" 2>/dev/null
  )"
  code=$?
  set -e
  printf '%s|%s\n' "$code" "$out"
}

_codex_platform_yaml='review:
  on_ready:
    github:
      - codex-github'
# A Greptile +1 reaction payload by the bot on the trigger comment —
# run_greptile_review's completion signal.
_greptile_reaction_json='[{"user":{"login":"greptile-apps[bot]"},"content":"+1"}]'
MOCK_HEAD_CONFIG="$_codex_platform_yaml"
MOCK_BASE_CONFIG="$_codex_platform_yaml"
MOCK_CHECK_RUNS='{"check_runs":[]}'
MOCK_PR_JSON="$_empty_rollup"

# Planted failing case 1: clean bot review on the head → label applies.
MOCK_REVIEWS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"commit_id":"'"$HEAD"'","state":"COMMENTED","body":"REVIEWED_COMMIT: '"$HEAD"'","submitted_at":"2026-01-02T00:00:00Z"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_clean_review_labels_exit" "0" "${result%%|*}"
run_test "codex_clean_review_labels_result" "labeled" "$(field "$result" RESULT)"
run_test "codex_clean_review_labels_reason" "gate-passed" "$(field "$result" REASON)"
run_test "codex_clean_review_applies_label" "1" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# Planted failing case 2: zero reviews by the bot on the head → fail closed
# (reviewer-check-absent), never a silent pass.
MOCK_REVIEWS='[]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_no_review_refuses_exit" "1" "${result%%|*}"
run_test "codex_no_review_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
run_test "codex_no_review_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# A CHANGES_REQUESTED review on the head is a blocking verdict.
MOCK_REVIEWS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"commit_id":"'"$HEAD"'","state":"CHANGES_REQUESTED","body":"","submitted_at":"2026-01-02T00:00:00Z"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_changes_requested_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
# A bot review for a DIFFERENT SHA is not evidence the current head was
# reviewed → refuse.
MOCK_REVIEWS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"commit_id":"bbbb222000000000000","state":"COMMENTED","body":"REVIEWED_COMMIT: bbbb222000000000000","submitted_at":"2026-01-02T00:00:00Z"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_other_sha_review_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
MOCK_REVIEWS='[]'

# coderabbit: same comment-only shape, plus its body classifier — a body with
# a blocking severity marker (🟠 Major) blocks; "No Issues Found" is clean;
# "✅ Addressed" findings do not block.
_rabbit_platform_yaml='review:
  on_ready:
    github:
      - coderabbit'
MOCK_HEAD_CONFIG="$_rabbit_platform_yaml"
MOCK_BASE_CONFIG="$_rabbit_platform_yaml"
MOCK_REVIEWS='[{"user":{"login":"coderabbitai"},"commit_id":"'"$HEAD"'","state":"COMMENTED","body":"Ready for review","submitted_at":"2026-01-02T00:00:00Z"}]'
MOCK_COMMENTS='[]'
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_clean_review_labels_result" "labeled" "$(field "$result" RESULT)"
# Blocking severity marker in an inline comment on the head.
MOCK_COMMENTS='[{"user":{"login":"coderabbitai"},"commit_id":"'"$HEAD"'","in_reply_to_id":null,"created_at":"2026-01-02T00:00:00Z","body":"🟠 Major: off-by-one in the guard"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_major_finding_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
run_test "coderabbit_major_finding_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# An Addressed finding is not blocking.
MOCK_COMMENTS='[{"user":{"login":"coderabbitai"},"commit_id":"'"$HEAD"'","in_reply_to_id":null,"created_at":"2026-01-02T00:00:00Z","body":"🟠 Major: off-by-one\n\n✅ Addressed in commit abc123"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_addressed_finding_not_blocking_result" "labeled" "$(field "$result" RESULT)"
# No coderabbit review at all → refuse.
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_no_review_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"

# A platform that is NOT documented (typo / unsupported) must still refuse
# reviewer-check-name-unresolved — the fail-closed typo guard survives.
MOCK_HEAD_CONFIG='review:
  on_ready:
    github:
      - totally-unknown-platform'
MOCK_BASE_CONFIG='review:
  on_ready:
    github:
      - totally-unknown-platform'
result="$(run_helper_platform "$_codex_config")"
run_test "unknown_platform_refuses_exit" "1" "${result%%|*}"
run_test "unknown_platform_refuses_reason" "reviewer-check-name-unresolved" "$(field "$result" REASON)"
run_test "unknown_platform_refuses_report" "totally-unknown-platform" "$(field "$result" REVIEWER_REPORT)"
run_test "unknown_platform_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"

# Check-run platforms keep resolving names: ronda (already covered) and the
# extended mapping — a codex-github run is NOT one, but claude-code-action
# (also comment-only) resolves to empty check name too. The named-platform
# regression guard: haystack/bugbot/ronda names are unchanged.
MOCK_HEAD_CONFIG=''
MOCK_BASE_CONFIG=''
MOCK_CHECK_RUNS="$_bugbot_ok"
result="$(run_helper)"
run_test "check_name_platforms_unchanged_result" "labeled" "$(field "$result" RESULT)"
MOCK_CHECK_RUNS="$_bugbot_ok"

MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS="$_bugbot_ok"
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[]'
MOCK_HEAD_CONFIG=''
MOCK_BASE_CONFIG=''

echo ""
echo "=== Area 16: PR #1818 codex-github findings, round 15 ==="

# The canonical Codex approved root-comment body, shared by the Area 16 and
# Area 17 fixtures: verdict sentence + the complete "About Codex in GitHub"
# details footer, exactly the shape CODEX_APPROVED_TEMPLATES whole-body
# matches (round 17, PRRT_kwDORWAxaM6m2604).
_codex_canonical_clean_body='Codex Review: Didn'"'"'t find any major issues. Swish! **Reviewed commit:** `'"$HEAD"'` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment "@codex review". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting "@codex address that feedback". </details>'

# Thread PRRT_kwDORWAxaM6m1pF4: the round-14 COMMENTED umbrella exemption
# only recognised Bugbot markers, so other comment-only reviewers' BLOCKING
# bodies skipped classification: run_devin_review() treats a COMMENTED body
# starting "**Devin Review**" as Devin's findings summary (blocking), and
# codex-github-reviewer.sh safe-fails every terminal "Codex Review:" body
# that is not the approved clean template. Planted failing case 1: a
# devin-style **Devin Review** COMMENTED body must block.
_devin_platform_yaml='review:
  on_ready:
    github:
      - devin'
MOCK_HEAD_CONFIG="$_devin_platform_yaml"
MOCK_BASE_CONFIG="$_devin_platform_yaml"
MOCK_CHECK_RUNS='{"check_runs":[]}'
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[{"user":{"login":"devin-ai-integration"},"id":500,"commit_id":"'"$HEAD"'","state":"COMMENTED","body":"**Devin Review**\n\nFound blocking issues: secrets committed.","submitted_at":"2026-01-02T00:00:00Z"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "devin_commented_body_blocks_exit" "1" "${result%%|*}"
run_test "devin_commented_body_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
run_test "devin_commented_body_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# Clean completion body (Devin's "No Issues Found") does not block.
MOCK_REVIEWS='[{"user":{"login":"devin-ai-integration"},"id":500,"commit_id":"'"$HEAD"'","state":"COMMENTED","body":"No Issues Found","submitted_at":"2026-01-02T00:00:00Z"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "devin_clean_body_labels_result" "labeled" "$(field "$result" RESULT)"
# Codex terminal body that is NOT the approved clean template blocks (the
# companion safe-fails unrecognized terminal bodies).
MOCK_HEAD_CONFIG="$_codex_platform_yaml"
MOCK_BASE_CONFIG="$_codex_platform_yaml"
MOCK_REVIEWS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"id":501,"commit_id":"'"$HEAD"'","state":"COMMENTED","body":"Codex Review: Needs fixes","submitted_at":"2026-01-02T00:00:00Z"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_unrecognized_terminal_body_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
# The approved clean sentence in a terminal body stays non-blocking.
_codex_review_json() {
  # _codex_review_json <state> <body> [id] [submitted_at] — one Codex review
  # object on the head (comma-join several into MOCK_REVIEWS).
  printf '%s' "$2" | jq -Rsc --arg st "$1" --arg sha "$HEAD" --argjson id "${3:-501}" --arg ts "${4:-2026-01-02T00:00:00Z}" \
    '{user:{login:"chatgpt-codex-connector[bot]"},id:$id,commit_id:$sha,state:$st,body:.,submitted_at:$ts}'
}
MOCK_REVIEWS="[$(_codex_review_json COMMENTED "$_codex_canonical_clean_body")]"
result="$(run_helper_platform "$_codex_config")"
run_test "codex_approved_terminal_body_labels_result" "labeled" "$(field "$result" RESULT)"
# Round 19 (PRRT_kwDORWAxaM6m5sk3): the PR-review path runs the canonical
# whole-body classifier — the clean sentence followed by later blocking text
# is NOT the approved template and must block (old: substring grep passed it).
MOCK_REVIEWS="[$(_codex_review_json COMMENTED "${_codex_canonical_clean_body} Must fix the guard before merge.")]"
result="$(run_helper_platform "$_codex_config")"
run_test "codex_clean_sentence_plus_must_fix_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
# Round 19 (PRRT_kwDORWAxaM6m5skr): a structured CHANGES_REQUESTED on the
# head survives a LATER informational COMMENTED review from the same bot.
MOCK_REVIEWS="[$(_codex_review_json CHANGES_REQUESTED "" 501 2026-01-02T00:00:00Z),$(_codex_review_json COMMENTED "$_codex_canonical_clean_body" 502 2026-01-03T00:00:00Z)]"
result="$(run_helper_platform "$_codex_config")"
run_test "changes_requested_survives_later_comment_reason" "blocking-findings" "$(field "$result" REASON)"
# ...but a later APPROVED review by the same bot supersedes it.
MOCK_REVIEWS="[$(_codex_review_json CHANGES_REQUESTED "" 501 2026-01-02T00:00:00Z),$(_codex_review_json APPROVED "" 503 2026-01-03T00:00:00Z)]"
result="$(run_helper_platform "$_codex_config")"
run_test "changes_requested_superseded_by_approved_result" "labeled" "$(field "$result" RESULT)"
# Round 24 (PRRT_kwDORWAxaM6m63Su): a nonempty Copilot APPROVED body is clean.
_copilot_yaml='review:
  on_ready:
    github:
      - copilot'
_saved_head_cfg="$MOCK_HEAD_CONFIG"; _saved_base_cfg="$MOCK_BASE_CONFIG"
MOCK_HEAD_CONFIG="$_copilot_yaml"; MOCK_BASE_CONFIG="$_copilot_yaml"
MOCK_REVIEWS='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"id":520,"commit_id":"'"$HEAD"'","state":"APPROVED","body":"Copilot reviewed 3 files and generated no comments.","submitted_at":"2026-01-02T00:00:00Z"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "copilot_approved_body_labels_result" "labeled" "$(field "$result" RESULT)"
MOCK_HEAD_CONFIG="$_saved_head_cfg"; MOCK_BASE_CONFIG="$_saved_base_cfg"
MOCK_REVIEWS='[]'

# Thread PRRT_kwDORWAxaM6m1pF_: non-review completion evidence for hosted
# comment-only reviewers. codex-github publishes its clean result as a
# SHA-pinned root PR comment (issue comment) — run_codex_github_review reads
# exactly that surface — so with no PR review the verdict must come from
# there, not refuse reviewer-check-absent forever. Planted failing case 2.
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS="$(printf '%s' "$_codex_canonical_clean_body" | jq -Rs --arg login 'chatgpt-codex-connector[bot]' '[{user:{login:$login},created_at:"2026-01-03T00:00:00Z",id:900,body:.}]')"
result="$(run_helper_platform "$_codex_config")"
run_test "codex_root_comment_completion_labels_exit" "0" "${result%%|*}"
run_test "codex_root_comment_completion_result" "labeled" "$(field "$result" RESULT)"
# The adapter still counts blocking findings the platform posted.
MOCK_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"commit_id":"'"$HEAD"'","pull_request_review_id":501,"in_reply_to_id":null,"created_at":"2026-01-04T00:00:00Z","body":"Rename the unsafe function."}]'
MOCK_REVIEWS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"id":501,"commit_id":"'"$HEAD"'","state":"CHANGES_REQUESTED","body":"","submitted_at":"2026-01-04T00:00:00Z"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_root_comment_with_findings_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
# A root comment pinned to a DIFFERENT SHA is not completion evidence for
# this head → fail closed.
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-03T00:00:00Z","id":900,"body":"Codex Review: Didn'\''t find any major issues. Swish! **Reviewed commit:** `bbbb222000000000000` <details> ... </details>"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_root_comment_other_sha_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
# Greptile completes by reacting to its trigger comment — run_greptile_review
# treats a bot +1 on the latest "@greptile review" comment as done. Planted
# failing case 3.
_greptile_platform_yaml='review:
  on_ready:
    github:
      - greptile'
MOCK_HEAD_CONFIG="$_greptile_platform_yaml"
MOCK_BASE_CONFIG="$_greptile_platform_yaml"
# Round 18 (thread PRRT_kwDORWAxaM6m36Wu): the trigger's cycle binding is the
# GraphQL PR timeline's SERVER-RECORDED order — the head commit's
# PullRequestCommit node must precede the trigger's IssueComment node. The
# fixture below is the normal shape: head commit first, trigger after.
_greptile_timeline_after_push='[{"__typename":"PullRequestCommit","commit":{"oid":"'"$HEAD"'"}},{"__typename":"IssueComment","databaseId":901,"createdAt":"2026-01-05T00:00:00Z","author":{"login":"agent"},"body":"@greptile review"}]'
MOCK_ISSUE_COMMENTS='[{"user":{"login":"agent"},"created_at":"2026-01-05T00:00:00Z","id":901,"body":"@greptile review"}]'
MOCK_PR_TIMELINE="$_greptile_timeline_after_push"
result="$(MOCK_GREPTILE_REACTION="$_greptile_reaction_json" run_helper_platform "$_codex_config")"
run_test "greptile_reaction_completion_labels_exit" "0" "${result%%|*}"
run_test "greptile_reaction_completion_result" "labeled" "$(field "$result" RESULT)"
# No reaction on the trigger comment → fail closed.
MOCK_GREPTILE_REACTION=''
result="$(run_helper_platform "$_codex_config")"
run_test "greptile_no_reaction_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
# Round 18 (PRRT_kwDORWAxaM6m36Wu): a trigger IssueComment node that the
# server ordered BEFORE the current head's PullRequestCommit node is a
# trigger from a prior cycle — GitHub only appends a commit node when it
# OBSERVES the push, so the ordering cannot be forged by backdating commit
# metadata (GIT_COMMITTER_DATE). Planted failing case: the backdated commit
# (committer date 2026-01-04, BEFORE the 2026-01-05 trigger) whose timeline
# node still comes after the trigger — the round-17 committer-date binding
# would accept this; the timeline binding must refuse.
MOCK_GREPTILE_REACTION="$_greptile_reaction_json"
MOCK_HEAD_COMMIT_JSON='{"commit":{"committer":{"date":"2026-01-04T00:00:00Z"}}}'
MOCK_PR_TIMELINE='[{"__typename":"IssueComment","databaseId":901,"createdAt":"2026-01-05T00:00:00Z","author":{"login":"agent"},"body":"@greptile review"},{"__typename":"PullRequestCommit","commit":{"oid":"'"$HEAD"'"}}]'
result="$(run_helper_platform "$_codex_config")"
run_test "greptile_backdated_commit_pre_push_trigger_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
run_test "greptile_backdated_commit_pre_push_trigger_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# The normal post-push trigger (timeline above) still labels with the same
# backdated committer date — proving the binding is the server timeline,
# not commit metadata.
MOCK_PR_TIMELINE="$_greptile_timeline_after_push"
result="$(run_helper_platform "$_codex_config")"
run_test "greptile_post_push_trigger_labels_result" "labeled" "$(field "$result" RESULT)"
# Round 19 (PRRT_kwDORWAxaM6m5slK): the timeline is paginated — the head
# commit on page 1 and the trigger only on page 2 must still label (old:
# last:100 omitted the anchor once >100 later events accumulated).
MOCK_PR_TIMELINE='[{"__typename":"PullRequestCommit","commit":{"oid":"'"$HEAD"'"}}]'
MOCK_PR_TIMELINE_PAGE2='[{"__typename":"IssueComment","databaseId":901,"createdAt":"2026-01-05T00:00:00Z","body":"@greptile review"}]'
MOCK_GREPTILE_REACTION="$_greptile_reaction_json"
MOCK_ISSUE_COMMENTS='[{"user":{"login":"agent"},"created_at":"2026-01-05T00:00:00Z","id":901,"body":"@greptile review"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "greptile_trigger_on_timeline_page2_labels_result" "labeled" "$(field "$result" RESULT)"
MOCK_PR_TIMELINE_PAGE2=''
MOCK_HEAD_COMMIT_JSON=''
MOCK_PR_TIMELINE=""
MOCK_ISSUE_COMMENTS='[]'

# Thread PRRT_kwDORWAxaM6m1pGF: the inline-comment scan must be bounded by
# the selected review's START, not its submission — inline comments created
# while the review was pending have created_at < submitted_at, so the old
# `>= submitted_at` bound excluded the review's own inline findings. Planted
# failing case 4: an inline comment created BEFORE submitted_at still counts.
MOCK_HEAD_CONFIG="$_codex_platform_yaml"
MOCK_BASE_CONFIG="$_codex_platform_yaml"
MOCK_ISSUE_COMMENTS='[]'
MOCK_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"commit_id":"'"$HEAD"'","pull_request_review_id":502,"in_reply_to_id":null,"created_at":"2026-01-02T00:00:00Z","body":"Rename the unsafe function."}]'
MOCK_REVIEWS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"id":502,"commit_id":"'"$HEAD"'","state":"COMMENTED","body":"REVIEWED_COMMIT: '"$HEAD"'","submitted_at":"2026-01-03T00:00:00Z"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "inline_comment_before_submitted_at_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
run_test "inline_comment_before_submitted_at_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# Time-bounding still required: an inline comment from a PREVIOUS run on the
# same SHA (created before the selected review AND its own review's window)
# must not block forever.
MOCK_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"commit_id":"'"$HEAD"'","pull_request_review_id":402,"in_reply_to_id":null,"created_at":"2026-01-01T00:00:00Z","body":"Rename the unsafe function."}]'
MOCK_REVIEWS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"id":402,"commit_id":"'"$HEAD"'","state":"COMMENTED","body":"REVIEWED_COMMIT: '"$HEAD"'","submitted_at":"2026-01-01T00:30:00Z"},{"user":{"login":"chatgpt-codex-connector[bot]"},"id":502,"commit_id":"'"$HEAD"'","state":"COMMENTED","body":"REVIEWED_COMMIT: '"$HEAD"'","submitted_at":"2026-01-03T00:00:00Z"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "previous_run_inline_comment_excluded_result" "labeled" "$(field "$result" RESULT)"
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'

echo ""
echo "=== Area 17: PR #1818 codex-github round-16 completion adapters ==="

# Thread PRRT_kwDORWAxaM6m2Os_: the round-15 codex root-comment marker match
# was an OR — a blocking verdict body ("Codex Review: Needs fixes ...
# Reviewed commit: <HEAD>") satisfied the "Reviewed commit" marker alone and
# passed clean. Planted failing case: a SHA-pinned BLOCKING root comment must
# refuse, never label, with the needs-fixes annotation applied.
MOCK_HEAD_CONFIG="$_codex_platform_yaml"
MOCK_BASE_CONFIG="$_codex_platform_yaml"
MOCK_PR_JSON="$_empty_rollup"
MOCK_CHECK_RUNS='{"check_runs":[]}'
MOCK_COMMENTS='[]'
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-03T00:00:00Z","id":910,"body":"Codex Review: Needs fixes. Must fix the guard before merge. **Reviewed commit:** `'"$HEAD"'`"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_root_comment_blocking_verdict_refuses_exit" "1" "${result%%|*}"
run_test "codex_root_comment_blocking_verdict_reason" "blocking-findings" "$(field "$result" REASON)"
run_test "codex_root_comment_blocking_verdict_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
run_test "codex_root_comment_blocking_verdict_annotated" "1" "$(grep -c 'add-label needs-fixes' "$_LABEL_LOG" || true)"
# Round 21 (PRRT_kwDORWAxaM6m6dJ1): an earlier clean REVIEW must not exempt
# the root-comment surface — a same-head rerun's newer blocking root verdict
# refuses; an OLDER blocking root verdict is superseded by the newer review.
MOCK_REVIEWS="[$(_codex_review_json COMMENTED "$_codex_canonical_clean_body" 501 2026-01-02T00:00:00Z)]"
result="$(run_helper_platform "$_codex_config")"
run_test "codex_review_plus_newer_blocking_root_refuses_reason" "blocking-findings" "$(field "$result" REASON)"
MOCK_ISSUE_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-01T00:00:00Z","id":911,"body":"Codex Review: Needs fixes. Must fix the guard before merge. **Reviewed commit:** `'"$HEAD"'`"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_review_supersedes_older_blocking_root_result" "labeled" "$(field "$result" RESULT)"
# Round 22 (PRRT_kwDORWAxaM6m6led): a same-head rerun's newer unavailability
# notice (no "Reviewed commit" marker) must not be masked by the older clean
# review; an older notice is superseded by the newer review.
MOCK_ISSUE_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-03T00:00:00Z","id":912,"body":"You have reached your Codex usage limits for code reviews."}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_review_plus_newer_usage_limit_refuses_reason" "reviewer-unavailable" "$(field "$result" REASON)"
MOCK_ISSUE_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-03T00:00:00Z","id":913,"body":"To use Codex here, create an environment for this repo."}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_review_plus_newer_env_error_refuses_reason" "reviewer-unavailable" "$(field "$result" REASON)"
MOCK_ISSUE_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-01T00:00:00Z","id":914,"body":"You have reached your Codex usage limits for code reviews."}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_review_supersedes_older_usage_limit_result" "labeled" "$(field "$result" RESULT)"
# A clean SHA-pinned root re-run AFTER the notice clears it (no deadlock).
MOCK_ISSUE_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-03T00:00:00Z","id":915,"body":"You have reached your Codex usage limits for code reviews."},{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-04T00:00:00Z","id":916,"body":'"$(printf '%s' "$_codex_canonical_clean_body" | jq -Rs .)"'}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_clean_root_rerun_clears_older_notice_result" "labeled" "$(field "$result" RESULT)"
# Round 23 (PRRT_kwDORWAxaM6m6vDx): the root-only completion path (no review
# object) also honors a NEWER unavailability notice after the clean root.
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-03T00:00:00Z","id":917,"body":'"$(printf '%s' "$_codex_canonical_clean_body" | jq -Rs .)"'},{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-04T00:00:00Z","id":918,"body":"You have reached your Codex usage limits for code reviews."}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_root_only_newer_usage_limit_refuses_reason" "reviewer-unavailable" "$(field "$result" REASON)"
MOCK_ISSUE_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-02T00:00:00Z","id":919,"body":"You have reached your Codex usage limits for code reviews."},{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-03T00:00:00Z","id":920,"body":'"$(printf '%s' "$_codex_canonical_clean_body" | jq -Rs .)"'}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_root_only_older_usage_limit_superseded_result" "labeled" "$(field "$result" RESULT)"
# Round 26 (PRRT_kwDORWAxaM6m7JN-): a strictly NEWER clean SHA-pinned root
# verdict supersedes an older CHANGES_REQUESTED review; an OLDER clean root
# does not (the newer change request still governs).
MOCK_REVIEWS="[$(_codex_review_json CHANGES_REQUESTED "" 501 2026-01-02T00:00:00Z)]"
MOCK_ISSUE_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-03T00:00:00Z","id":921,"body":'"$(printf '%s' "$_codex_canonical_clean_body" | jq -Rs .)"'}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_newer_clean_root_supersedes_change_request_result" "labeled" "$(field "$result" RESULT)"
MOCK_ISSUE_COMMENTS='[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-01-01T00:00:00Z","id":922,"body":'"$(printf '%s' "$_codex_canonical_clean_body" | jq -Rs .)"'}]'
result="$(run_helper_platform "$_codex_config")"
run_test "codex_older_clean_root_keeps_change_request_reason" "blocking-findings" "$(field "$result" REASON)"
MOCK_REVIEWS='[]'
MOCK_REVIEWS='[]'
# The clean sentence AND the head pin together still pass (unchanged
# behavior) — but round 17 (PRRT_kwDORWAxaM6m2604) requires the body to
# match the canonical CODEX_APPROVED_TEMPLATES whole-body exact template,
# not the clean sentence alone. The fixture is the full canonical approved
# body (verdict sentence + complete "About Codex in GitHub" details
# footer), defined once in Area 16 (_codex_canonical_clean_body).'Codex Review: Didn'"'"'t find any major issues. Swish! **Reviewed commit:** `'"$HEAD"'` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> [Your team has set up Codex to review pull requests in this repo](https://chatgpt.com/codex/cloud/settings/general). Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment "@codex review". If Codex has suggestions, it will comment; otherwise it will react with 👍. Codex can also answer questions or update the PR. Try commenting "@codex address that feedback". </details>'
MOCK_ISSUE_COMMENTS="$(printf '%s' "$_codex_canonical_clean_body" | jq -Rs --arg login 'chatgpt-codex-connector[bot]' '[{user:{login:$login},created_at:"2026-01-03T00:00:00Z",id:911,body:.}]')"
result="$(run_helper_platform "$_codex_config")"
run_test "codex_root_comment_clean_verdict_labels_result" "labeled" "$(field "$result" RESULT)"
# Planted failing case (PRRT_kwDORWAxaM6m2604): the clean sentence PLUS
# injected blocking text ("Must fix ...") satisfies the round-16 substring
# match but never the canonical whole-body template — must refuse/block,
# never label.
MOCK_ISSUE_COMMENTS="$(printf '%s' "$_codex_canonical_clean_body" | jq -Rs --arg login 'chatgpt-codex-connector[bot]' '[{user:{login:$login},created_at:"2026-01-03T00:00:00Z",id:912,body:(. + " Must fix the guard before merge.")}]')"
result="$(run_helper_platform "$_codex_config")"
run_test "codex_root_comment_clean_plus_injected_must_fix_reason" "blocking-findings" "$(field "$result" REASON)"
run_test "codex_root_comment_clean_plus_injected_must_fix_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"

# Thread PRRT_kwDORWAxaM6m2OtD: claude-code-action passes the allow-list but
# had no completion adapter, so a successful run read as a permanent
# reviewer-check-absent. Planted failing case 1: a successful
# workflow_dispatch run for the PR labels.
_claude_action_platform_yaml='review:
  on_ready:
    github:
      - claude-code-action'
MOCK_HEAD_CONFIG="$_claude_action_platform_yaml"
MOCK_BASE_CONFIG="$_claude_action_platform_yaml"
MOCK_ISSUE_COMMENTS='[]'
_claude_run_success='{"id":700,"name":"Claude Code Review — PR #42","path":".github/workflows/claude-code-review.yml","event":"workflow_dispatch","status":"completed","conclusion":"success","created_at":"2026-01-06T00:00:00Z","head_sha":"'"$HEAD"'"}'
# Round 20 (PRRT_kwDORWAxaM6m6Vnb): real Runs API shape — name is the
# workflow name, display_title carries the run-name. A NEWER run for another
# PR must not be selected in place of this PR's current-head success.
_claude_run_dt_mine='{"id":710,"name":"Claude Code Review","display_title":"Claude Code Review — PR #42","path":".github/workflows/claude-code-review.yml","event":"workflow_dispatch","status":"completed","conclusion":"success","created_at":"2026-01-06T00:00:00Z","head_sha":"'"$HEAD"'"}'
_claude_run_dt_other='{"id":711,"name":"Claude Code Review","display_title":"Claude Code Review — PR #43","path":".github/workflows/claude-code-review.yml","event":"workflow_dispatch","status":"completed","conclusion":"success","created_at":"2026-01-07T00:00:00Z","head_sha":"ffff000000000000000"}'
result="$(MOCK_WORKFLOW_RUNS="${_claude_run_dt_other},${_claude_run_dt_mine}" MOCK_RUN_LOG='Trigger result: true' run_helper_platform "$_codex_config")"
run_test "claude_display_title_scopes_pr_result" "labeled" "$(field "$result" RESULT)"
result="$(MOCK_WORKFLOW_RUNS="$_claude_run_success" MOCK_RUN_LOG='Trigger result: true' run_helper_platform "$_codex_config")"
run_test "claude_action_run_success_labels_exit" "0" "${result%%|*}"
run_test "claude_action_run_success_result" "labeled" "$(field "$result" RESULT)"
# Planted failing case (PRRT_kwDORWAxaM6m260w): a successful run bound to a
# DIFFERENT head certifies that prior head, never the current one — must
# refuse.
_claude_run_stale_head='{"id":703,"name":"Claude Code Review — PR #42","path":".github/workflows/claude-code-review.yml","event":"workflow_dispatch","status":"completed","conclusion":"success","created_at":"2026-01-06T00:00:00Z","head_sha":"bbbb222000000000000"}'
result="$(MOCK_WORKFLOW_RUNS="$_claude_run_stale_head" MOCK_RUN_LOG='Trigger result: true' run_helper_platform "$_codex_config")"
run_test "claude_action_run_stale_head_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
run_test "claude_action_run_stale_head_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# Planted failing case (PRRT_kwDORWAxaM6m260z): conclusion=success alone is
# not execution proof — a run whose log shows the no-op marker must refuse.
result="$(MOCK_WORKFLOW_RUNS="$_claude_run_success" MOCK_RUN_LOG='Context prompt: NO PROMPT' run_helper_platform "$_codex_config")"
run_test "claude_action_run_noop_success_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
# And a run whose log cannot be fetched fails closed too.
result="$(MOCK_WORKFLOW_RUNS="$_claude_run_success" MOCK_RUN_LOG_EXIT=1 run_helper_platform "$_codex_config")"
run_test "claude_action_run_unreadable_log_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
# Planted failing case 2: a FAILED run must refuse (fail closed).
_claude_run_failure='{"id":701,"name":"Claude Code Review — PR #42","path":".github/workflows/claude-code-review.yml","event":"workflow_dispatch","status":"completed","conclusion":"failure","created_at":"2026-01-06T00:00:00Z","head_sha":"'"$HEAD"'"}'
result="$(MOCK_WORKFLOW_RUNS="$_claude_run_failure" run_helper_platform "$_codex_config")"
run_test "claude_action_run_failure_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
# Planted failing case 3: no run at all must refuse.
result="$(MOCK_WORKFLOW_RUNS="" run_helper_platform "$_codex_config")"
run_test "claude_action_no_run_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
# An in-progress run is not completion evidence either.
_claude_run_inprogress='{"id":702,"name":"Claude Code Review — PR #42","path":".github/workflows/claude-code-review.yml","event":"workflow_dispatch","status":"in_progress","conclusion":null,"created_at":"2026-01-06T00:00:00Z","head_sha":"'"$HEAD"'"}'
result="$(MOCK_WORKFLOW_RUNS="$_claude_run_inprogress" run_helper_platform "$_codex_config")"
run_test "claude_action_run_inprogress_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
# Blocking review state posted by the bot still blocks a successful run.
MOCK_REVIEWS='[{"user":{"login":"claude[bot]"},"id":600,"commit_id":"'"$HEAD"'","state":"CHANGES_REQUESTED","body":"","submitted_at":"2026-01-07T00:00:00Z"}]'
result="$(MOCK_WORKFLOW_RUNS="$_claude_run_success" MOCK_RUN_LOG='Trigger result: true' run_helper_platform "$_codex_config")"
run_test "claude_action_run_with_changes_requested_blocks_reason" "blocking-findings" "$(field "$result" REASON)"
# Round 28 (PRRT_kwDORWAxaM6nBlmk): an existing review must not bypass the
# Actions-run adapter — a newer queued/no-op rerun refuses; a verified
# successful run with the review present still labels.
MOCK_REVIEWS='[{"user":{"login":"claude[bot]"},"id":601,"commit_id":"'"$HEAD"'","state":"COMMENTED","body":"","submitted_at":"2026-01-07T00:00:00Z"}]'
result="$(MOCK_WORKFLOW_RUNS="$_claude_run_inprogress" run_helper_platform "$_codex_config")"
run_test "claude_review_plus_inprogress_rerun_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
result="$(MOCK_WORKFLOW_RUNS="$_claude_run_success" MOCK_RUN_LOG='Context prompt: NO PROMPT' run_helper_platform "$_codex_config")"
run_test "claude_review_plus_noop_rerun_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
result="$(MOCK_WORKFLOW_RUNS="$_claude_run_success" MOCK_RUN_LOG='Trigger result: true' run_helper_platform "$_codex_config")"
run_test "claude_review_plus_verified_run_labels_result" "labeled" "$(field "$result" RESULT)"
# Round 30 (PRRT_kwDORWAxaM6nCAK_): a nonempty Claude APPROVED body with a
# verified run is clean.
MOCK_REVIEWS='[{"user":{"login":"claude[bot]"},"id":602,"commit_id":"'"$HEAD"'","state":"APPROVED","body":"LGTM - reviewed the change, no issues.","submitted_at":"2026-01-07T00:00:00Z"}]'
result="$(MOCK_WORKFLOW_RUNS="$_claude_run_success" MOCK_RUN_LOG='Trigger result: true' run_helper_platform "$_codex_config")"
run_test "claude_approved_body_labels_result" "labeled" "$(field "$result" RESULT)"
# Round 30 (PRRT_kwDORWAxaM6nCAK8): a DISMISSED bodyless review is no verdict —
# a review-only platform (copilot) with only that review refuses absent.
_saved_head_cfg2="$MOCK_HEAD_CONFIG"; _saved_base_cfg2="$MOCK_BASE_CONFIG"
MOCK_HEAD_CONFIG="$_copilot_yaml"; MOCK_BASE_CONFIG="$_copilot_yaml"
MOCK_REVIEWS='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"id":603,"commit_id":"'"$HEAD"'","state":"DISMISSED","body":"","submitted_at":"2026-01-07T00:00:00Z"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "dismissed_bodyless_review_is_not_verdict_reason" "reviewer-check-absent" "$(field "$result" REASON)"
MOCK_HEAD_CONFIG="$_saved_head_cfg2"; MOCK_BASE_CONFIG="$_saved_base_cfg2"
MOCK_REVIEWS='[]'
MOCK_REVIEWS='[]'
MOCK_REVIEWS='[]'

# Thread PRRT_kwDORWAxaM6m2OtK: pr-agent / coderabbit-cli / local-ai-reviewer.
# pr-agent's adapter reads the bot's SHA-pinned "PR Reviewer Guide" comment
# and applies run_pr_agent_review's label classification. Planted failing
# case 1: a clean summary comment ("No major issues detected") labels.
_pr_agent_platform_yaml='review:
  on_ready:
    github:
      - pr-agent'
MOCK_HEAD_CONFIG="$_pr_agent_platform_yaml"
MOCK_BASE_CONFIG="$_pr_agent_platform_yaml"
MOCK_ISSUE_COMMENTS='[{"user":{"login":"github-actions[bot]"},"created_at":"2026-01-08T00:00:00Z","id":920,"body":"## PR Reviewer Guide\n\ncommit: '"$HEAD"'\nNo major issues detected"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "pr_agent_clean_comment_labels_exit" "0" "${result%%|*}"
# Round 25 (PRRT_kwDORWAxaM6m6_DC): an unrelated COMMENTED review by the
# shared github-actions[bot] login must NOT count as PR-Agent completion when
# no PR Reviewer Guide comment exists.
MOCK_REVIEWS='[{"user":{"login":"github-actions[bot]"},"id":530,"commit_id":"'"$HEAD"'","state":"COMMENTED","body":"unrelated automation summary","submitted_at":"2026-01-02T00:00:00Z"}]'
MOCK_ISSUE_COMMENTS='[]'
result="$(run_helper_platform "$_codex_config")"
run_test "pr_agent_unrelated_shared_login_review_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
MOCK_REVIEWS='[]'
MOCK_ISSUE_COMMENTS='[{"user":{"login":"github-actions[bot]"},"created_at":"2026-01-08T00:00:00Z","id":920,"body":"## PR Reviewer Guide\n\ncommit: '"$HEAD"'\nNo major issues detected"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "pr_agent_clean_comment_labels_result" "labeled" "$(field "$result" RESULT)"
# Planted failing case 2: a hard-blocker focus label refuses.
MOCK_ISSUE_COMMENTS='[{"user":{"login":"github-actions[bot]"},"created_at":"2026-01-08T00:00:00Z","id":921,"body":"## PR Reviewer Guide\n\ncommit: '"$HEAD"'\n### Recommended focus areas for review\n<td><tr><strong>Security Concern</strong></td></tr>"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "pr_agent_hard_blocker_comment_refuses_reason" "blocking-findings" "$(field "$result" REASON)"
run_test "pr_agent_hard_blocker_comment_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# Advisory-only labels stay clean (the loop's advisory rule).
MOCK_ISSUE_COMMENTS='[{"user":{"login":"github-actions[bot]"},"created_at":"2026-01-08T00:00:00Z","id":922,"body":"## PR Reviewer Guide\n\ncommit: '"$HEAD"'\n### Recommended focus areas for review\n<td><tr><strong>Possible Issue</strong></td></tr>"}]'
result="$(run_helper_platform "$_codex_config")"
run_test "pr_agent_advisory_comment_labels_result" "labeled" "$(field "$result" RESULT)"
# No matching comment → fail closed.
MOCK_ISSUE_COMMENTS='[]'
result="$(run_helper_platform "$_codex_config")"
run_test "pr_agent_no_comment_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"

# coderabbit-cli / local-ai-reviewer (PRRT_kwDORWAxaM6m260s): these
# reviewers are pure CLI (no check run, no review, no issue comment), so
# the loop's DURABLE current-head evidence is the reviewer_loop_history.v1
# ledger posted inside the "Automated Reviewer Loop Summary" issue
# comment. A current-head clean verdict there labels; anything else —
# absent summary, stale head, needs_fixes — refuses. The summary comment
# fixture below carries the marker + json fence the shared extract
# helpers read.
_ledger_platform='coderabbit-cli'
_ledger_entry() {
  # _ledger_entry <result> <reviewed_head> <iteration>
  printf '### Automated Reviewer Loop Summary\n\n*Posted automatically by `pr-review-loop.sh`.*\n\nIteration %s\n\n<!-- reviewer-loop-history:v1 -->\n```json\n{"schema":"reviewer_loop_history.v1","entries":[{"iteration":%s,"updated_at":"2026-01-09T00:00:00Z","platform_results":[{"platform":"%s","result":"%s"}],"reviewed_heads":[{"platform":"%s","reviewed_head":"%s","state":"complete"}]}]}\n```\n' "$3" "$3" "$_ledger_platform" "$1" "$_ledger_platform" "$2"
}
MOCK_HEAD_CONFIG='review:
  on_ready:
    github:
      - coderabbit-cli'
MOCK_BASE_CONFIG='review:
  on_ready:
    github:
      - coderabbit-cli'
# Round 18 (thread PRRT_kwDORWAxaM6m36Wn): the ledger summary comment must
# be authenticated — the marker strings are public, so ANY participant can
# forge a body. The trusted-actor definition: the comment's author is the
# login the loop itself posts under (the invoker's own `gh api user` login
# — gh pr comment / gh api PATCH carry that token) OR GitHub reports
# author_association OWNER / MEMBER / COLLABORATOR. _ledger_comment wraps a
# ledger body with a chosen author login + association.
_ledger_comment() {
  # _ledger_comment <login> <association> <id> <body>
  printf '%s' "$4" | jq -Rs --arg login "$1" --arg assoc "$2" --argjson cid "$3" \
    '[{user:{login:$login},author_association:$assoc,created_at:"2026-01-09T00:00:00Z",id:$cid,body:.}]'
}
# The loop's trusted poster: the invoker login the gh stub reports
# (MOCK_GH_USER default loop-runner), OWNER association as GitHub reports it.
MOCK_GH_USER='loop-runner'
# Planted failing case 1 (old code: blanket refusal — clean current-head
# evidence must label): a clean ledger verdict pinned to the current head,
# posted by the loop's trusted actor (invoker login, OWNER).
MOCK_ISSUE_COMMENTS="$(_ledger_comment loop-runner OWNER 930 "$(_ledger_entry clean "$HEAD" 3)")"
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_cli_current_head_ledger_labels_exit" "0" "${result%%|*}"
run_test "coderabbit_cli_current_head_ledger_labels_result" "labeled" "$(field "$result" RESULT)"
# Round 18 (PRRT_kwDORWAxaM6m36Wn) planted failing case: a FORGED ledger —
# the exact same marker strings + current-head clean payload, but posted by
# a regular participant (CONTRIBUTOR association, not the invoker's login).
# Old code (body-markers-only selection) labelled this; the authenticated
# selection must refuse.
MOCK_ISSUE_COMMENTS="$(_ledger_comment mallory CONTRIBUTOR 934 "$(_ledger_entry clean "$HEAD" 3)")"
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_cli_forged_untrusted_author_ledger_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
run_test "coderabbit_cli_forged_untrusted_author_ledger_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# A NON-COLLABORATOR participant (NONE association, not the invoker login)
# is equally untrusted — refused even with a perfect body.
MOCK_ISSUE_COMMENTS="$(_ledger_comment random-drive-by NONE 935 "$(_ledger_entry clean "$HEAD" 3)")"
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_cli_none_association_ledger_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
# A trusted association the invoker does NOT own (a repo COLLABORATOR) is
# still the loop's trust domain — the loop can be run by any collaborator.
MOCK_PERMS='trusted-collaborator=write'
MOCK_ISSUE_COMMENTS="$(_ledger_comment trusted-collaborator COLLABORATOR 936 "$(_ledger_entry clean "$HEAD" 3)")"
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_cli_collaborator_ledger_labels_result" "labeled" "$(field "$result" RESULT)"
# Round 19 (PRRT_kwDORWAxaM6m5slC): a COLLABORATOR/MEMBER ASSOCIATION alone
# is not write capability — a read-permission collaborator (and one whose
# permission lookup fails) is untrusted and its ledger is refused.
MOCK_PERMS='trusted-collaborator=read'
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_cli_read_permission_ledger_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
MOCK_PERMS=''
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_cli_lookup_failed_ledger_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
MOCK_ISSUE_COMMENTS="$(_ledger_comment member-user MEMBER 938 "$(_ledger_entry clean "$HEAD" 3)")"
MOCK_PERMS='member-user=read'
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_cli_member_read_ledger_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
MOCK_PERMS='trusted-collaborator=write'
MOCK_ISSUE_COMMENTS="$(_ledger_comment trusted-collaborator COLLABORATOR 936 "$(_ledger_entry clean "$HEAD" 3)")"
# A forged NEWER comment by an untrusted author must not shadow a trusted
# one: the newest TRUSTED record is selected, and the forged entry is
# ignored — labels (the forged entry claims needs_fixes, older trusted one
# is clean; clean labels, proving the forged newer comment was skipped).
MOCK_ISSUE_COMMENTS="$(
  {
    _ledger_comment loop-runner OWNER 930 "$(_ledger_entry clean "$HEAD" 2)"
    _ledger_comment mallory CONTRIBUTOR 937 "$(_ledger_entry needs_fixes "$HEAD" 4)"
  } | jq -s 'add'
)"
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_cli_forged_newer_comment_shadowed_result" "labeled" "$(field "$result" RESULT)"
# Planted failing case 2: a clean verdict pinned to a DIFFERENT head is
# stale — must refuse, never label (posted by the trusted actor).
MOCK_ISSUE_COMMENTS="$(_ledger_comment loop-runner OWNER 931 "$(_ledger_entry clean bbbb222000000000000 3)")"
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_cli_stale_head_ledger_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
run_test "coderabbit_cli_stale_head_ledger_no_label" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
# Planted failing case 3: a needs_fixes verdict on the current head blocks
# / refuses.
MOCK_ISSUE_COMMENTS="$(_ledger_comment loop-runner OWNER 932 "$(_ledger_entry needs_fixes "$HEAD" 3)")"
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_cli_needs_fixes_ledger_refuses_reason" "reviewer-evidence-unreadable" "$(field "$result" REASON)"
# No summary comment at all → absent evidence, fail closed.
MOCK_ISSUE_COMMENTS='[]'
result="$(run_helper_platform "$_codex_config")"
run_test "coderabbit_cli_no_ledger_refuses_reason" "reviewer-check-absent" "$(field "$result" REASON)"
# local-ai-reviewer: the same ledger mechanism (one representative case:
# current-head clean labels; the round-16 blanket refusal is gone), posted
# by the trusted actor.
_ledger_platform='local-ai-reviewer'
MOCK_HEAD_CONFIG='review:
  on_ready:
    github:
      - local-ai-reviewer'
MOCK_BASE_CONFIG='review:
  on_ready:
    github:
      - local-ai-reviewer'
MOCK_ISSUE_COMMENTS="$(_ledger_comment loop-runner OWNER 933 "$(_ledger_entry clean "$HEAD" 3)")"
result="$(run_helper_platform "$_codex_config")"
run_test "local_ai_reviewer_current_head_ledger_labels_result" "labeled" "$(field "$result" RESULT)"
MOCK_ISSUE_COMMENTS='[]'
MOCK_GH_USER=''
MOCK_PERMS=''

echo ""
echo "$pass passed, $fail failed"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
