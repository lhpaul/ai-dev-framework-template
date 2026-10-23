#!/usr/bin/env bash
# shellcheck shell=bash
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
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Fixtures own reviewer policy. A valid synthetic source without declarations
# prevents workstation overrides from replacing the mocked base policy.
ISOLATED_OVERRIDE_ROOT="$TMP_ROOT/no-local-overrides"
mkdir -p "$ISOLATED_OVERRIDE_ROOT"
printf 'review: {}\n' >"$ISOLATED_OVERRIDE_ROOT/.ai-dev-workflow.local.yaml"
export WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$ISOLATED_OVERRIDE_ROOT"
unset AI_DEV_WORKFLOW_CONFIG_FILE

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
    if grep -q -- "--remove-label" <<< "$*"; then
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
  *"HeadRefForcePushedEvent"*)
    # Round 31 (PRRT_kwDORWAxaM6nCTd8): head-occupancy timeline. When
    # MOCK_OCC_TIMELINE is set it is served verbatim as the nodes array;
    # otherwise the stub synthesizes the ordinary single-occupancy history:
    # the head commit node followed by every MOCK_ISSUE_COMMENTS comment.
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    [ "${MOCK_OCC_TIMELINE_EXIT:-0}" = "0" ] || exit 1
    if [ -n "${MOCK_OCC_TIMELINE:-}" ]; then
      _nodes="$MOCK_OCC_TIMELINE"
    else
      _nodes="$(jq -cn --argjson ic "[${MOCK_ISSUE_COMMENTS:-[]}]" --argjson rv "[${MOCK_REVIEWS:-[]}]" '[{"__typename":"PullRequestCommit","commit":{"oid":"aaaa111000000000000"}}] + [ $rv[][]? | {"__typename":"PullRequestReview","databaseId":(.id // 0)} ] + [ $ic[][]? | {"__typename":"IssueComment","databaseId":(.id // 0)} ]')"
    fi
    if [ -n "${MOCK_OCC_TIMELINE_PAGE2:-}" ]; then
      printf '%s\n' "[{\"data\":{\"repository\":{\"pullRequest\":{\"timelineItems\":{\"nodes\":${_nodes}}}}}},{\"data\":{\"repository\":{\"pullRequest\":{\"timelineItems\":{\"nodes\":${MOCK_OCC_TIMELINE_PAGE2}}}}}}]"
    else
      printf '%s\n' "[{\"data\":{\"repository\":{\"pullRequest\":{\"timelineItems\":{\"nodes\":${_nodes}}}}}}]"
    fi
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
    # order). MOCK_OCC_TIMELINE carries the timelineItems nodes array; the
    # stub applies the caller's --jq filter itself (emit would re-apply it
    # to the already-filtered nodes).
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    [ "${MOCK_OCC_TIMELINE_EXIT:-0}" = "0" ] || exit 1
    # Round 19 (PRRT_kwDORWAxaM6m5slK): the helper now paginates (--paginate
    # --slurp), so the stub emits an ARRAY OF PAGES. MOCK_OCC_TIMELINE_PAGE2,
    # when set, is a second page's nodes (the head commit can sit on page 1
    # with the trigger only on page 2).
    if [ -n "${MOCK_OCC_TIMELINE_PAGE2:-}" ]; then
      printf '%s\n' "[{\"data\":{\"repository\":{\"pullRequest\":{\"timelineItems\":{\"nodes\":${MOCK_OCC_TIMELINE:-[]}}}}}},{\"data\":{\"repository\":{\"pullRequest\":{\"timelineItems\":{\"nodes\":${MOCK_OCC_TIMELINE_PAGE2}}}}}}]"
    else
      printf '%s\n' "[{\"data\":{\"repository\":{\"pullRequest\":{\"timelineItems\":{\"nodes\":${MOCK_OCC_TIMELINE:-[]}}}}}}]"
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
  *"pr view"*"--json headRefName,headRepositoryOwner,headRepository,isCrossRepository"*)
    # PR ownership guard (#1837, pr-ownership-guard.sh via apply-readiness-labels.sh).
    # MOCK_OWNERSHIP_PR_JSON overrides the whole payload for dedicated ownership
    # tests; otherwise the default derives headRefName from MOCK_PR_JSON so every
    # pre-existing readiness fixture's ownership check passes by construction
    # (it reports the same branch the readiness fixture already declares) and
    # the owning repository matches the default acme/widgets fixture repo.
    printf '%s\n' "$*" >>"${MOCK_CALL_LOG:-/dev/null}" 2>/dev/null || true
    if [ -n "${MOCK_OWNERSHIP_PR_JSON:-}" ]; then
      emit "$MOCK_OWNERSHIP_PR_JSON"
    else
      _own_branch="$(printf '%s\n' "${MOCK_PR_JSON:-$pr_default}" | jq -r '.headRefName // empty' 2>/dev/null)"
      [ -n "$_own_branch" ] || _own_branch='fix/1408-demo'
      printf '{"headRefName":"%s","headRepositoryOwner":{"login":"acme"},"headRepository":{"name":"widgets"},"isCrossRepository":%s}\n' \
        "$_own_branch" "${MOCK_OWNERSHIP_CROSS:-false}"
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
  # Ownership branch: derived from MOCK_PR_JSON's own headRefName (falling
  # back to $_BRANCH) so the ownership guard (#1837) matches every fixture's
  # own PR state by construction — the gate this wrapper exercises is the
  # reviewer/CI gate, not ownership. MOCK_OWNERSHIP_BRANCH overrides it for
  # dedicated ownership-mismatch tests.
  local _ownership_branch="${MOCK_OWNERSHIP_BRANCH:-}"
  if [ -z "$_ownership_branch" ]; then
    _ownership_branch="$(printf '%s\n' "${MOCK_PR_JSON:-}" | jq -r '.headRefName // empty' 2>/dev/null)"
    [ -n "$_ownership_branch" ] || _ownership_branch="$_BRANCH"
  fi
  local _dry_run_flag=()
  [ "${MOCK_DRY_RUN:-false}" = "true" ] && _dry_run_flag=(--dry-run)
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
    MOCK_OWNERSHIP_PR_JSON="${MOCK_OWNERSHIP_PR_JSON:-}" \
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
    MOCK_OCC_TIMELINE="${MOCK_OCC_TIMELINE:-}" \
    MOCK_OCC_TIMELINE_PAGE2="${MOCK_OCC_TIMELINE_PAGE2:-}" \
    MOCK_REVIEW_THREADS="${MOCK_REVIEW_THREADS:-}" \
    MOCK_REVIEW_THREADS_EXIT="${MOCK_REVIEW_THREADS_EXIT:-0}" \
    MOCK_OCC_TIMELINE_EXIT="${MOCK_OCC_TIMELINE_EXIT:-0}" \
    MOCK_PERMS="${MOCK_PERMS:-}" \
    PR_AGENT_BOT_LOGIN="${PR_AGENT_BOT_LOGIN:-github-actions[bot]}" \
    "$HELPER" --pr 42 --repo acme/widgets --branch "$_ownership_branch" --label "$label" "${_dry_run_flag[@]+"${_dry_run_flag[@]}"}" 2>/dev/null
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


run_helper_no_local_config() {
  local label="${MOCK_LABEL:-ready-for-human-review}"
  local _ownership_branch="${MOCK_OWNERSHIP_BRANCH:-}"
  if [ -z "$_ownership_branch" ]; then
    _ownership_branch="$(printf '%s\n' "${MOCK_PR_JSON:-}" | jq -r '.headRefName // empty' 2>/dev/null)"
    [ -n "$_ownership_branch" ] || _ownership_branch="$_BRANCH"
  fi
  : >"$_LABEL_LOG"
  : >"$_LABEL_STATE"
  : >"$_CALL_LOG"
  set +e
  out="$(
    PATH="$_BIN:$PATH" \
    WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="${MOCK_LOCAL_OVERRIDE_ROOT:-$ISOLATED_OVERRIDE_ROOT}" \
    MOCK_GH_LOG="$_LABEL_LOG" \
    MOCK_CALL_LOG="$_CALL_LOG" \
    MOCK_LABEL_STATE="$_LABEL_STATE" \
    MOCK_PR_JSON="${MOCK_PR_JSON:-}" \
    MOCK_OWNERSHIP_PR_JSON="${MOCK_OWNERSHIP_PR_JSON:-}" \
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
    "$HELPER" --pr 42 --repo acme/widgets --branch "$_ownership_branch" --label "$label" 2>/dev/null
  )"
  code=$?
  set -e
  printf '%s|%s\n' "$code" "$out"
}

run_helper_platform() {
  local label="${MOCK_LABEL:-ready-for-human-review}"
  local _ownership_branch="${MOCK_OWNERSHIP_BRANCH:-}"
  if [ -z "$_ownership_branch" ]; then
    _ownership_branch="$(printf '%s\n' "${MOCK_PR_JSON:-}" | jq -r '.headRefName // empty' 2>/dev/null)"
    [ -n "$_ownership_branch" ] || _ownership_branch="$_BRANCH"
  fi
  : >"$_LABEL_LOG"
  : >"$_LABEL_STATE"
  : >"$_CALL_LOG"
  : >"${TMP_ROOT:-/tmp}/gh-user.cache"
  set +e
  out="$(
    PATH="$_BIN:$PATH" \
    WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$ISOLATED_OVERRIDE_ROOT" \
    MOCK_GH_LOG="$_LABEL_LOG" \
    MOCK_CALL_LOG="$_CALL_LOG" \
    MOCK_LABEL_STATE="$_LABEL_STATE" \
    MOCK_PR_JSON="${MOCK_PR_JSON:-}" \
    MOCK_OWNERSHIP_PR_JSON="${MOCK_OWNERSHIP_PR_JSON:-}" \
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
    MOCK_OCC_TIMELINE="${MOCK_OCC_TIMELINE:-}" \
    MOCK_OCC_TIMELINE_PAGE2="${MOCK_OCC_TIMELINE_PAGE2:-}" \
    MOCK_REVIEW_THREADS="${MOCK_REVIEW_THREADS:-}" \
    MOCK_REVIEW_THREADS_EXIT="${MOCK_REVIEW_THREADS_EXIT:-0}" \
    MOCK_OCC_TIMELINE_EXIT="${MOCK_OCC_TIMELINE_EXIT:-0}" \
    MOCK_PERMS="${MOCK_PERMS:-}" \
    PR_AGENT_BOT_LOGIN="${PR_AGENT_BOT_LOGIN:-github-actions[bot]}" \
    "$HELPER" --pr 42 --repo acme/widgets --branch "$_ownership_branch" --label "$label" 2>/dev/null
  )"
  code=$?
  set -e
  printf '%s|%s\n' "$code" "$out"
}
