#!/usr/bin/env bash
# test-pr-review-loop-pr-agent-coderabbit.sh — pr-review-loop.sh harness: PR-
# Agent and CodeRabbit platforms, post-clean settle, late threads, current-
# head evidence.
# duration: 55
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
#
# The pr-review-loop.sh harness is split across these suites (#1876), which
# share their preamble — snapshot re-exec, --area filter, gh/git mocks, the
# HARNESS_MODE source of pr-review-loop.sh, and the run_test helpers — through
# tests/lib/pr-review-loop-harness.sh:
#
#   test-pr-review-loop.sh
#   test-pr-review-loop-cycles-labels.sh
#   test-pr-review-loop-failure-paths-1.sh
#   test-pr-review-loop-failure-paths-2.sh
#   test-pr-review-loop-failure-paths-3.sh
#   test-pr-review-loop-failure-paths-4.sh
#   test-pr-review-loop-release-bugbot.sh
#   test-pr-review-loop-pr-agent-coderabbit.sh
#   test-pr-review-loop-staged-gates.sh
#   test-pr-review-loop-no-verdict-yet.sh
#
# Areas in this suite:
#   Area 17: PR-Agent explicit trigger model
#   Area: coderabbit_success_status_count (issue #1437)
#   Area: coderabbit_no_trigger_timeout_default (issue #1433)
#   Area: coderabbit_resolve_no_trigger_timeout (issue #1433)
#   Area: CodeRabbit skip-banner false-clean (issue #1531)
#   Area 19: post-clean settle and updated_at activity (#1556)
#   Area 20: late-thread re-check contract (#1574)
#   Area 14: CodeRabbit rate-limit window parsing (issue #1579)
#   Area 1648: reviewer-loop current-head evidence
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop-pr-agent-coderabbit.sh [--area <name>]... [--list-areas]
# No external tooling required beyond bash, git, and jq (git only locates the
# repository root at startup; mock gh commands replace all network calls).
#
# Exit code: 0 if all tests pass, 1 if any test fails, 2 on a usage error.
#
# Many assignments here set pr-review-loop.sh globals that the functions under
# test read. ShellCheck does not follow that source, so each such assignment
# carries its own `# shellcheck disable=SC2034` with the reason inline.

set -euo pipefail

# Resolve the shared harness from the checked-in suite path. Inside a snapshot
# run $0 is a temp copy, so TEST_PR_REVIEW_LOOP_ORIGIN (set by the harness on
# re-exec, or by hand for an out-of-tree copy) takes precedence.
_prl_harness="$(dirname -- "${TEST_PR_REVIEW_LOOP_ORIGIN:-$0}")/lib/pr-review-loop-harness.sh"
if [ ! -f "$_prl_harness" ]; then
  echo "ERROR: shared harness not found: $_prl_harness" >&2
  echo "  Run the checked-in suite, or set TEST_PR_REVIEW_LOOP_ORIGIN to its path." >&2
  exit 2
fi
# shellcheck source=scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
source "$_prl_harness" "$@"
unset _prl_harness

# Carried state. In the single-file harness, Area 13 exported this for every
# later area; keep the suites that held those areas running under the same
# environment so the split changes where tests live, not what they exercise.
export CODEX_GITHUB_PRE_TRIGGER_WAIT=0

# Carried state: Area 15 (test-pr-review-loop-release-bugbot.sh) left this
# exported for every later area in the single-file harness.
export MOCK_GH_OUTPUT='[]'

# ---------------------------------------------------------------------------
# Area 17: PR-Agent explicit trigger model
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 17: PR-Agent explicit trigger model ==="

_pr_agent_mock_dir_1701="$(mktemp -d)"
_pr_agent_call_log_1701="$_pr_agent_mock_dir_1701/calls.log"
cat > "$_pr_agent_mock_dir_1701/gh" <<'PR_AGENT_GH_1701'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PR_AGENT_CALL_LOG"
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1701sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"-X POST"*"issues/42/comments"*)
    printf '{"created_at":"2020-01-01T00:00:01Z"}\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
PR_AGENT_GH_1701
chmod +x "$_pr_agent_mock_dir_1701/gh"

actual_output="$(
  PATH="$_pr_agent_mock_dir_1701:$PATH" PR_AGENT_CALL_LOG="$_pr_agent_call_log_1701" \
    run_pr_agent_review "42" "feature/42-test" "1" "0" || true
)"
run_test "pr_agent_posts_explicit_trigger" "PR_AGENT_TRIGGER_COMMENT=/review" \
  "$(printf '%s\n' "$actual_output" | grep "^PR_AGENT_TRIGGER_COMMENT=")"
run_test "pr_agent_no_review_after_trigger_skips" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "pr_agent_trigger_post_call_made" "1" \
  "$(grep_count_or_zero "-X POST repos/.*/issues/42/comments" "$_pr_agent_call_log_1701")"
rm -rf "$_pr_agent_mock_dir_1701"
unset _pr_agent_mock_dir_1701 _pr_agent_call_log_1701 actual_output

_pr_agent_mock_dir_1702="$(mktemp -d)"
_pr_agent_call_log_1702="$_pr_agent_mock_dir_1702/calls.log"
cat > "$_pr_agent_mock_dir_1702/gh" <<'PR_AGENT_GH_1702'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PR_AGENT_CALL_LOG"
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1702000000000000000000000000000000000\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"issues/42/comments"*)
    # #1789 (plan D15 rule (a)): the summary is bound to the head by its
    # visible marker line, not by the SHA appearing anywhere in the body.
    printf '[{"user":{"login":"github-actions[bot]"},"updated_at":"2020-01-01T00:00:02Z","html_url":"https://example.test/comment","body":"PR Reviewer Guide\\n#### (Review updated until commit https://github.com/owner/repo/commit/abc1702000000000000000000000000000000000)\\nNo major issues detected"}]\n'
    exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
PR_AGENT_GH_1702
chmod +x "$_pr_agent_mock_dir_1702/gh"

actual_output="$(
  PATH="$_pr_agent_mock_dir_1702:$PATH" PR_AGENT_CALL_LOG="$_pr_agent_call_log_1702" \
    run_pr_agent_review "42" "feature/42-test" "1" "0" || true
)"
run_test "pr_agent_reuses_existing_comment" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "pr_agent_existing_comment_no_duplicate_trigger" "0" \
  "$(grep_count_or_zero "-X POST repos/.*/issues/42/comments" "$_pr_agent_call_log_1702")"
rm -rf "$_pr_agent_mock_dir_1702"
unset _pr_agent_mock_dir_1702 _pr_agent_call_log_1702 actual_output

_pr_agent_mock_dir_1703="$(mktemp -d)"
_pr_agent_call_log_1703="$_pr_agent_mock_dir_1703/calls.log"
cat > "$_pr_agent_mock_dir_1703/gh" <<'PR_AGENT_GH_1703'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PR_AGENT_CALL_LOG"
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1703sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1703sha/check-runs"*)
    printf '{"check_runs":[]}\n{"check_runs":[{"name":"PR-Agent review","status":"in_progress"}]}\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
PR_AGENT_GH_1703
chmod +x "$_pr_agent_mock_dir_1703/gh"

actual_output="$(
  PATH="$_pr_agent_mock_dir_1703:$PATH" PR_AGENT_CALL_LOG="$_pr_agent_call_log_1703" \
    run_pr_agent_review "42" "feature/42-test" "1" "0" || true
)"
run_test "pr_agent_active_check_no_duplicate_trigger" "PR_AGENT_TRIGGER_SKIPPED=active_review_in_progress" \
  "$(printf '%s\n' "$actual_output" | grep "^PR_AGENT_TRIGGER_SKIPPED=")"
run_test "pr_agent_active_check_waits_then_skips" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "pr_agent_active_check_no_post_call" "0" \
  "$(grep_count_or_zero "-X POST repos/.*/issues/42/comments" "$_pr_agent_call_log_1703")"
rm -rf "$_pr_agent_mock_dir_1703"
unset _pr_agent_mock_dir_1703 _pr_agent_call_log_1703 actual_output

_pr_agent_mock_dir_1704="$(mktemp -d)"
_pr_agent_call_log_1704="$_pr_agent_mock_dir_1704/calls.log"
cat > "$_pr_agent_mock_dir_1704/gh" <<'PR_AGENT_GH_1704'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PR_AGENT_CALL_LOG"
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1704sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1704sha/check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '[{"id":1704,"user":{"login":"lhpaul"},"created_at":"2020-01-01T00:00:01Z","updated_at":"2020-01-01T00:00:01Z","body":"/review"}]\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
PR_AGENT_GH_1704
chmod +x "$_pr_agent_mock_dir_1704/gh"

# #1789 (plan D15): only a trigger recorded for the head is reused, so the
# loop hands its id over in reviewer_loop_head_request_refs.
actual_output="$(
  # shellcheck disable=SC2034  # read by functions sourced from pr-review-loop.sh
  reviewer_loop_head_request_refs="1704"
  PATH="$_pr_agent_mock_dir_1704:$PATH" PR_AGENT_CALL_LOG="$_pr_agent_call_log_1704" \
    PR_AGENT_TRIGGER_REUSE_WINDOW_SECONDS=999999999 \
    run_pr_agent_review "42" "feature/42-test" "1" "0" || true
)"
run_test "pr_agent_recent_trigger_no_duplicate_trigger" "PR_AGENT_TRIGGER_SKIPPED=recent_review_trigger" \
  "$(printf '%s\n' "$actual_output" | grep "^PR_AGENT_TRIGGER_SKIPPED=")"
run_test "pr_agent_recent_trigger_waits_then_skips" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "pr_agent_recent_trigger_no_post_call" "0" \
  "$(grep_count_or_zero "-X POST repos/.*/issues/42/comments" "$_pr_agent_call_log_1704")"
rm -rf "$_pr_agent_mock_dir_1704"
unset _pr_agent_mock_dir_1704 _pr_agent_call_log_1704 actual_output

_pr_agent_mock_dir_1705="$(mktemp -d)"
_pr_agent_call_log_1705="$_pr_agent_mock_dir_1705/calls.log"
cat > "$_pr_agent_mock_dir_1705/gh" <<'PR_AGENT_GH_1705'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PR_AGENT_CALL_LOG"
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1705sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1705sha/check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  *"-X POST"*"issues/42/comments"*)
    printf '{"created_at":"2026-06-30T00:00:00Z"}\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '[{"user":{"login":"lhpaul"},"created_at":"2020-01-01T00:00:01Z","updated_at":"2020-01-01T00:00:01Z","body":"/review"}]\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
PR_AGENT_GH_1705
chmod +x "$_pr_agent_mock_dir_1705/gh"

actual_output="$(
  PATH="$_pr_agent_mock_dir_1705:$PATH" PR_AGENT_CALL_LOG="$_pr_agent_call_log_1705" \
    PR_AGENT_TRIGGER_REUSE_WINDOW_SECONDS=1 \
    run_pr_agent_review "42" "feature/42-test" "1" "0" || true
)"
run_test "pr_agent_stale_trigger_posts_new_trigger" "PR_AGENT_TRIGGER_COMMENT=/review" \
  "$(printf '%s\n' "$actual_output" | grep "^PR_AGENT_TRIGGER_COMMENT=")"
run_test "pr_agent_stale_trigger_post_call_made" "1" \
  "$(grep_count_or_zero "-X POST repos/.*/issues/42/comments" "$_pr_agent_call_log_1705")"
rm -rf "$_pr_agent_mock_dir_1705"
unset _pr_agent_mock_dir_1705 _pr_agent_call_log_1705 actual_output

_pr_agent_mock_dir_1706="$(mktemp -d)"
cat > "$_pr_agent_mock_dir_1706/gh" <<'PR_AGENT_GH_1706'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1706sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1706sha/check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  *"-X POST"*"issues/42/comments"*)
    exit 1 ;;
  *"issues/42/comments"*)
    printf '[]\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
PR_AGENT_GH_1706
chmod +x "$_pr_agent_mock_dir_1706/gh"

actual_output="$(
  PATH="$_pr_agent_mock_dir_1706:$PATH" run_pr_agent_review "42" "feature/42-test" "1" "0" || true
)"
run_test "pr_agent_trigger_failure_escalates" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "pr_agent_trigger_failure_reason" "REASON=pr_agent_trigger_failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
rm -rf "$_pr_agent_mock_dir_1706"
unset _pr_agent_mock_dir_1706 actual_output

# These two assertions check the pr-agent companion workflow, which only
# exists in repositories that actually run pr-agent as a Step 7 GitHub
# reviewer. A consumer that syncs this template but keeps pr-agent out of
# review.on_*.github (or ships a workflow_dispatch-only overlay) has no reason
# to satisfy them, and failing there turned a successful sync into a red
# required check (#1631). Gate on the live config, not on the template default.
if workflow_config_review_github_reviewer_configured "pr-agent" "$REPO_ROOT/.ai-dev-workflow.yaml"; then
  run_test "pr_agent_workflow_synchronize_trigger" "1" \
    "$(grep_count_or_zero "types:.*synchronize" "$REPO_ROOT/.github/workflows/pr-agent.yml")"
  run_test "pr_agent_workflow_exact_review_command" "1" \
    "$(grep_count_or_zero "github.event.comment.body == '/review'" "$REPO_ROOT/.github/workflows/pr-agent.yml")"
else
  echo "SKIP: pr_agent_workflow_synchronize_trigger - pr-agent is not a configured Step 7 GitHub reviewer in this repository"
  echo "SKIP: pr_agent_workflow_exact_review_command - pr-agent is not a configured Step 7 GitHub reviewer in this repository"
fi

# ---------------------------------------------------------------------------
# Area: coderabbit_success_status_count (issue #1437)
#
# Verifies the shared helper used by both coderabbit_status_success_fallback
# call sites in run_coderabbit_review rejects a `success` commit status whose
# description indicates the review was rate-limited / did not actually run,
# while still counting a genuine success status as clean evidence. Uses the
# same MOCK_GH_OUTPUT single-array pattern as Area 2 (check_unreplied_rest_comments):
# --paginate | jq -s flattens via .[].[] so a single JSON array is sufficient.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area: coderabbit_success_status_count (issue #1437) ==="

unset MOCK_GH_POST_EXIT MOCK_GH_POST_OUTPUT MOCK_GH_CALL_LOG MOCK_GH_EXIT

# CONTROL: genuine success status with a normal description — must count as 1.
# This is the "still reports clean for a genuine success description" direction.
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"Review completed: 0 findings","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_genuine_success" "1" "$actual"

# PLANTED VIOLATION: success status whose description is CodeRabbit's confirmed
# rate-limit banner text — must NOT count (0), proving the false-clean hole from
# issue #1437 is closed. Before this fix, checking .state alone would have
# returned 1 here (false clean).
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"Review limit reached. Next review available in: 43 minutes","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_rate_limited_description_rejected" "0" "$actual"

# Rate-limit description with different casing and hyphen separator — regex is
# the same test("rate.?limit"; "i") pattern already used elsewhere in this script.
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"RATE-LIMIT: try again later","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_rate_limit_hyphen_case_insensitive" "0" "$actual"

# Each alternative in the "rate.?limit|review limit|next review available"
# regex must independently reject on its own — tested in isolation so a future
# accidental removal of one alternative is caught even if the other two still
# pass. "review limit" alone (no "rate limit" or "next review available" text).
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"Review limit exceeded for this repository","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_review_limit_phrase_alone_rejected" "0" "$actual"

# "next review available" alone (no "rate limit" or "review limit" text).
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"Please retry — next review available shortly","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_next_review_available_phrase_alone_rejected" "0" "$actual"

# Non-success state is never counted regardless of description.
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"pending","description":"Reviewing...","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_pending_not_counted" "0" "$actual"

# Missing/null description on a genuine success status must still count (no
# regression for the common case where CodeRabbit sets no description at all).
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_missing_description_still_counts" "1" "$actual"

# Dedup by context: an older genuine success is superseded by a newer
# rate-limited success on the same context — only the latest (rejected) entry
# should be considered, so the count must be 0.
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"Review completed: 0 findings","updated_at":"2026-08-10T00:00:00Z"},{"context":"coderabbit/review","state":"success","description":"Review limit reached. Next review available in: 10 minutes","updated_at":"2026-08-10T00:05:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_dedup_latest_rate_limited" "0" "$actual"

# Dedup by context: an older rate-limited success is superseded by a newer
# genuine success on the same context — the count must be 1.
export MOCK_GH_OUTPUT='[{"context":"coderabbit/review","state":"success","description":"Review limit reached. Next review available in: 10 minutes","updated_at":"2026-08-10T00:00:00Z"},{"context":"coderabbit/review","state":"success","description":"Review completed: 0 findings","updated_at":"2026-08-10T00:05:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_dedup_latest_genuine" "1" "$actual"

# Non-coderabbit context is ignored entirely.
export MOCK_GH_OUTPUT='[{"context":"ci/build","state":"success","description":"rate limit exceeded","updated_at":"2026-08-10T00:00:00Z"}]'
actual="$(coderabbit_success_status_count "owner/repo" "abc123")"
run_test "coderabbit_success_status_count_non_coderabbit_context_ignored" "0" "$actual"

# Argument validation: empty repo or head_sha must short-circuit before the
# `gh api` call (asserted via MOCK_GH_CALL_LOG — the mock's default fallback
# returns "[]"/exit 0 for ANY input, so checking only the return value/exit
# code would pass even without the guard; the call-log assertion is what
# actually proves the guard prevents the API call) and must safely return "0"
# rather than propagating a nonzero exit status, since both call sites assign
# this function's output via `var="$(coderabbit_success_status_count ...)"`
# under `set -euo pipefail`, where a nonzero return would abort the whole
# reviewer-loop script instead of falling through to the normal "no success
# status found" path.
unset MOCK_GH_OUTPUT
_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log"
actual="$(coderabbit_success_status_count "" "abc123")"
actual_exit=$?
run_test "coderabbit_success_status_count_empty_repo_returns_zero" "0" "$actual"
run_test "coderabbit_success_status_count_empty_repo_exit_zero" "0" "$actual_exit"
run_test "coderabbit_success_status_count_empty_repo_no_api_call" "" "$(cat "$_call_log")"
rm -f "$_call_log"
unset MOCK_GH_CALL_LOG

_call_log="$(mktemp)"
export MOCK_GH_CALL_LOG="$_call_log"
actual="$(coderabbit_success_status_count "owner/repo" "")"
actual_exit=$?
run_test "coderabbit_success_status_count_empty_head_sha_returns_zero" "0" "$actual"
run_test "coderabbit_success_status_count_empty_head_sha_exit_zero" "0" "$actual_exit"
run_test "coderabbit_success_status_count_empty_head_sha_no_api_call" "" "$(cat "$_call_log")"
rm -f "$_call_log"
unset MOCK_GH_CALL_LOG

# ---------------------------------------------------------------------------
# Area: coderabbit_no_trigger_timeout_default (issue #1433)
#
# Verifies the computed default for the CodeRabbit silent-non-trigger fallback
# timeout (scripts/development-workflow/pr-review-loop.sh lines 3989-4004).
# Prior behavior: a fixed 600 s default, decoupled from --max-wait. Two bugs
# this fixes: (1) latency — 600 s of pure idle wait before the proactive
# "@coderabbitai review" nudge on the common default max_wait=1200 invocation;
# (2) correctness — on short-max_wait invocations (e.g. the 180 s doc-branch
# default) elapsed could never reach 600 before the outer max_wait exit, so
# the silent-non-trigger safety net could never fire at all.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area: coderabbit_no_trigger_timeout_default (issue #1433) ==="

# CONTROL / latency fix: the common default invocation (max_wait=1200, the
# hardcoded default in main()) must now yield 180 — a 420 s (7 min) reduction
# from the old fixed 600 s default. half_max_wait=600 does not cap the 180 s
# hardcoded default, so the hardcoded value wins.
actual="$(coderabbit_no_trigger_timeout_default 1200)"
run_test "no_trigger_timeout_default_common_max_wait_1200" "180" "$actual"

# PLANTED VIOLATION / correctness fix: doc-branch default max_wait=180. Under
# the OLD fixed-600 default, elapsed could never reach 600 before the loop's
# own "elapsed >= max_wait" (180) exit fires first — the silent-non-trigger
# retrigger block (pr-review-loop.sh ~line 4315,
# `coderabbit_no_trigger_retriggers < ... && elapsed >= coderabbit_no_trigger_timeout`)
# would be permanently unreachable on these branches. The half-max_wait cap
# (line 3996) must produce 90 (half of 180, below the 180 hardcoded default)
# so the fallback has room to fire with a full max_wait/2 remaining for a
# subsequent poll cycle. Reverting the cap (deleting lines 3994-3999, leaving
# only the hardcoded 180 default) makes this assertion fail — 180 is not < 180
# under `--max-wait 180`, so the retrigger could never fire before timeout;
# this was manually verified during implementation (see PR description) and
# is the concrete regression this test guards against.
actual="$(coderabbit_no_trigger_timeout_default 180)"
run_test "no_trigger_timeout_default_doc_branch_max_wait_180_capped" "90" "$actual"

# Large-diff invocation (max_wait=2400): half is 1200, well above the 180
# hardcoded default, so the cap must NOT kick in — the hardcoded default wins.
actual="$(coderabbit_no_trigger_timeout_default 2400)"
run_test "no_trigger_timeout_default_large_diff_max_wait_2400_uncapped" "180" "$actual"

# Floor: a pathologically small max_wait (40) yields half_max_wait=20, below
# the 30 s floor (line 4000-4002) — the floor must win over the smaller capped
# value so at least one nudge attempt has a usable window.
actual="$(coderabbit_no_trigger_timeout_default 40)"
run_test "no_trigger_timeout_default_floor_applies_below_30" "30" "$actual"

# Boundary: max_wait=360 -> half=180, exactly equal to the hardcoded default.
# The cap only applies when half_max_wait is STRICTLY less than the hardcoded
# default (line 3996 uses `-lt`), so at the boundary the hardcoded default
# must still be the result (not fall through to some other branch).
actual="$(coderabbit_no_trigger_timeout_default 360)"
run_test "no_trigger_timeout_default_boundary_max_wait_360" "180" "$actual"

# Invalid/empty max_wait must safely fall back to the hardcoded default
# instead of crashing on arithmetic with a non-numeric value.
actual="$(coderabbit_no_trigger_timeout_default "")"
run_test "no_trigger_timeout_default_empty_max_wait_fallback" "180" "$actual"

actual="$(coderabbit_no_trigger_timeout_default "not-a-number")"
run_test "no_trigger_timeout_default_non_numeric_max_wait_fallback" "180" "$actual"

# Zero max_wait must not attempt a division-relevant cap and must fall back to
# the hardcoded default (guarded by `-gt 0` on line 3994).
actual="$(coderabbit_no_trigger_timeout_default 0)"
run_test "no_trigger_timeout_default_zero_max_wait_fallback" "180" "$actual"

# Leading-zero decimal input (CodeRabbit finding on PR #1458): "080" passes
# the ^[0-9]+$ digit-only regex guard but, without base-10 normalization, bash
# arithmetic expansion parses a leading-zero literal as octal — and "080" is
# not a valid octal literal (8 is not an octal digit), so `$((080 / 2))`
# errors with "value too great for base" and aborts the script under
# `set -euo pipefail`. The `10#$max_wait` prefix forces base-10 interpretation
# so this must safely compute 40 (half of 80) instead of erroring.
actual="$(coderabbit_no_trigger_timeout_default 080)"
run_test "no_trigger_timeout_default_leading_zero_max_wait_normalized_base10" "40" "$actual"

# ---------------------------------------------------------------------------
# Area: coderabbit_resolve_no_trigger_timeout (issue #1433, CodeRabbit finding
# on PR #1458) — exercises the actual production override-resolution path
# used by run_coderabbit_review, not just the underlying default-computation
# helper tested above.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area: coderabbit_resolve_no_trigger_timeout (issue #1433) ==="

# No override set: must fall through to coderabbit_no_trigger_timeout_default.
unset CODERABBIT_NO_TRIGGER_TIMEOUT
actual="$(coderabbit_resolve_no_trigger_timeout 180)"
run_test "no_trigger_resolve_no_override_uses_computed_default" "90" "$actual"

# An explicit override larger than the computed default for the given
# max_wait must be honored as-is (uncapped) rather than silently reduced —
# same pattern already used by CODERABBIT_RATE_LIMIT_WAIT / _MAX_RETRIES.
export CODERABBIT_NO_TRIGGER_TIMEOUT=900
actual="$(coderabbit_resolve_no_trigger_timeout 180)"
run_test "no_trigger_resolve_explicit_override_honored_uncapped" "900" "$actual"
unset CODERABBIT_NO_TRIGGER_TIMEOUT

# An invalid explicit override (non-numeric) must fall back to the computed
# default (with a WARN to stderr, not asserted here) rather than propagating
# a bad value or crashing the script.
export CODERABBIT_NO_TRIGGER_TIMEOUT="not-a-number"
actual="$(coderabbit_resolve_no_trigger_timeout 180 2>/dev/null)"
run_test "no_trigger_resolve_invalid_override_falls_back_to_default" "90" "$actual"
unset CODERABBIT_NO_TRIGGER_TIMEOUT

# A zero explicit override (fails the `-le 0` guard) must also fall back.
export CODERABBIT_NO_TRIGGER_TIMEOUT=0
actual="$(coderabbit_resolve_no_trigger_timeout 1200 2>/dev/null)"
run_test "no_trigger_resolve_zero_override_falls_back_to_default" "180" "$actual"
unset CODERABBIT_NO_TRIGGER_TIMEOUT

# ---------------------------------------------------------------------------
# Area: CodeRabbit "Review skipped" banner is not review activity (issue #1531)
#
# CodeRabbit posts a "Review skipped" banner instead of a review whenever it
# declines by configuration rather than by capacity (auto_review.enabled false,
# drafts excluded, or base_branches not matching the PR base). Before this fix
# the activity probe in run_coderabbit_review excluded only the pause,
# rate-limit, and resume markers, so the skip banner read as "CodeRabbit posted
# something", broke the poll loop into Phase 3, and Phase 3 returned
# RESULT=clean after collecting zero inline comments — a clean verdict on a PR
# CodeRabbit never looked at.
#
# The end-to-end case runs with poll_interval=1, max_wait=3 and
# CODERABBIT_NO_TRIGGER_TIMEOUT=1 so the loop exercises the explicit-nudge path
# and then its timeout branch — where the skip-banner guard lives — within a few
# seconds of real sleep.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area: CodeRabbit skip-banner false-clean (issue #1531) ==="

unset MOCK_GH_OUTPUT MOCK_GH_POST_EXIT MOCK_GH_POST_OUTPUT MOCK_GH_CALL_LOG MOCK_GH_EXIT

# The exact banner CodeRabbit posts when reviews.auto_review.enabled is false,
# quoted from an observed comment on this repository (PR #1527).
_CR_SKIP_BANNER_1531='<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!IMPORTANT]\n> ## Review skipped\n> \n> Auto reviews are disabled on this repository. Please check the settings in the CodeRabbit UI or the `.coderabbit.yaml` file in this repository. To trigger a single review, invoke the `@coderabbitai review` command.'

# --- AC-1: the regex classifies banners, not genuine reviews ------------------
_cr_re_matches_1531() {
  printf '%s' "$1" \
    | jq -Rs --arg skip_re "$CODERABBIT_SKIP_BANNER_RE" \
        'if test($skip_re; "i") then "yes" else "no" end' -r
}

run_test "cr_skip_banner_re_matches_auto_reviews_disabled" "yes" \
  "$(_cr_re_matches_1531 "$_CR_SKIP_BANNER_1531")"

# The "Review skipped" half must match on its own: CodeRabbit uses the same
# heading for the drafts-excluded and base-branch-mismatch variants, whose
# bodies never contain the "auto reviews are disabled" sentence.
run_test "cr_skip_banner_re_matches_review_skipped_alone" "yes" \
  "$(_cr_re_matches_1531 '> [!IMPORTANT]
> ## Review skipped
>
> Draft detected. Set `reviews.auto_review.drafts` to true to review draft PRs.')"

# CONTROL: a BARE "## Review skipped" heading, with no blockquote prefix, is not
# a banner. A genuine CodeRabbit comment may legitimately use that heading, and
# classifying it as a banner would drop a real review from the activity probe.
run_test "cr_skip_banner_re_ignores_bare_heading" "no" \
  "$(_cr_re_matches_1531 '## Review skipped

This section explains when the reviewer skips generated files.')"

# CONTROL: a genuine CodeRabbit walkthrough must NOT match, or the fix would
# suppress real reviews and hang every loop until timeout.
run_test "cr_skip_banner_re_ignores_genuine_walkthrough" "no" \
  "$(_cr_re_matches_1531 '## Walkthrough

The changes update the reviewer loop. Estimated code review effort: 3.')"

# CONTROL: the word "skipped" in ordinary review prose must not match either.
run_test "cr_skip_banner_re_ignores_prose_use_of_skipped" "no" \
  "$(_cr_re_matches_1531 'Nitpick: this branch is skipped when the list is empty.')"

# CONTROL, and the reason the pattern is not a bare "review skipped" substring:
# a genuine walkthrough may use that exact phrase in prose. Matching it would be
# the mirror-image failure — a real review classified as a banner, ignored by the
# activity probe, polled to timeout, and escalated.
run_test "cr_skip_banner_re_ignores_exact_phrase_in_prose" "no" \
  "$(_cr_re_matches_1531 'The walkthrough notes that this review skipped the generated files.')"

# The HTML marker CodeRabbit stamps on skip comments (and on no other kind) is
# the most reliable signal, and must match on its own even if the rendered
# heading text is reworded by the vendor.
run_test "cr_skip_banner_re_matches_html_marker_alone" "yes" \
  "$(_cr_re_matches_1531 '<!-- This is an auto-generated comment: skip review by coderabbit.ai -->')"

# The pattern is consumed by BOTH jq (test(); Oniguruma) and grep -qiE (POSIX
# ERE). A pattern valid in only one engine would silently stop matching at one of
# the two call sites, so the engines are asserted to agree.
_cr_grep_matches_1531() {
  if grep -qiE "$CODERABBIT_SKIP_BANNER_RE" <<< "$1"; then echo yes; else echo no; fi
}
run_test "cr_skip_banner_re_grep_agrees_on_banner" "yes" \
  "$(_cr_grep_matches_1531 '> ## Review skipped')"
run_test "cr_skip_banner_re_grep_agrees_on_bare_heading" "no" \
  "$(_cr_grep_matches_1531 '## Review skipped')"
run_test "cr_skip_banner_re_grep_agrees_on_prose" "no" \
  "$(_cr_grep_matches_1531 'The walkthrough notes that this review skipped the generated files.')"

# --- AC-1: the activity probe returns 0 for a banner-only comment set ---------
# Mirrors the production jq expression in run_coderabbit_review so a future edit
# that drops the $skip_re clause is caught here.
_cr_activity_count_1531() {
  printf '%s' "$1" \
    | jq -s --arg bot "coderabbitai[bot]" --arg since "2020-01-01T00:00:00Z" \
         --arg skip_re "$CODERABBIT_SKIP_BANNER_RE" '
        [.[].[] | select(
            .user.login == $bot and
            .created_at > $since and
            ((.body // "") | test("Reviews paused|review paused"; "i") | not) and
            ((.body // "") | test("rate.?limit"; "i") | not) and
            ((.body // "") | test("reviews resumed"; "i") | not) and
            ((.body // "") | test($skip_re; "i") | not)
        )] | length
      '
}

run_test "cr_activity_probe_skip_banner_not_activity" "0" \
  "$(_cr_activity_count_1531 "$(jq -cn --arg b "$_CR_SKIP_BANNER_1531" \
       '[{user:{login:"coderabbitai[bot]"},created_at:"2020-01-01T00:00:01Z",body:$b}]')")"

run_test "cr_activity_probe_genuine_review_is_activity" "1" \
  "$(_cr_activity_count_1531 "$(jq -cn \
       '[{user:{login:"coderabbitai[bot]"},created_at:"2020-01-01T00:00:01Z",body:"## Walkthrough\n\nLGTM."}]')")"

# --- AC-2 / AC-3: end-to-end escalation instead of a clean verdict ------------
_cr_mock_dir_1531="$(mktemp -d)"
_cr_call_log_1531="$_cr_mock_dir_1531/calls.log"
cat > "$_cr_mock_dir_1531/gh" <<'CR_GH_1531'
#!/usr/bin/env bash
# Strict mock: every gh invocation run_coderabbit_review legitimately makes is
# enumerated, and anything else is a hard error. A permissive "*) echo []" fallback
# would let these cases pass for the wrong reason — a renamed or dropped comments
# request would silently return an empty array and still produce the expected
# REASON, proving nothing.
printf '%s\n' "$*" >> "$CR_CALL_LOG"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'abc1531sha\n'; exit 0 ;;
  *"commits/abc1531sha --jq .commit.committer.date"*) printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1531sha/statuses"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '%s\n' '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:01Z","updated_at":"2020-01-01T00:00:01Z","body":"<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!IMPORTANT]\n> ## Review skipped\n>\n> Auto reviews are disabled on this repository."}]'
    exit 0 ;;
  *"api graphql"*)
    printf '%s\n' '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}'
    exit 0 ;;
  *"pr comment 42"*) exit 0 ;;
  *)
    printf 'UNEXPECTED gh invocation in 1531 mock: %s\n' "$*" >&2
    exit 1 ;;
esac
CR_GH_1531
chmod +x "$_cr_mock_dir_1531/gh"

actual_output="$(
  PATH="$_cr_mock_dir_1531:$PATH" CR_CALL_LOG="$_cr_call_log_1531" \
    CODERABBIT_NO_TRIGGER_TIMEOUT=1 \
    CODERABBIT_RATE_LIMIT_WAIT=1 CODERABBIT_RATE_LIMIT_MIN_WAIT=1 \
    run_coderabbit_review "42" "fix/42-test" "1" "3" 2>/dev/null || true
)"

# The planted violation: before the fix this asserted RESULT=clean.
run_test "cr_skip_banner_escalates_not_clean" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"

# A distinct REASON from rate_limit_max_retries — the operator fix is a
# .coderabbit.yaml change, not waiting out a vendor quota.
run_test "cr_skip_banner_reason_is_review_skipped_banner" "REASON=review_skipped_banner" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"

# The mock errors on any unenumerated call, but silence is not proof the RIGHT
# call happened — assert the comments endpoint was actually requested.
run_test "cr_skip_banner_queried_issue_comments" "yes" \
  "$([ "$(grep_count_or_zero "issues/42/comments" "$_cr_call_log_1531")" -ge 1 ] && echo yes || echo no)"

# AC-2: the loop must still have nudged CodeRabbit with an explicit trigger
# before giving up, since "@coderabbitai review" works even when auto review is
# disabled. Without the activity-probe fix the loop broke out immediately and
# never reached the retrigger path.
_cr_trigger_count_1531="$(grep_count_or_zero "pr comment 42 --body @coderabbitai review" "$_cr_call_log_1531")"
run_test "cr_skip_banner_posts_explicit_review_trigger" "yes" \
  "$([ "$_cr_trigger_count_1531" -ge 1 ] && echo yes || echo no)"

# The nudge must stay bounded by CODERABBIT_RATE_LIMIT_MAX_RETRIES rather than
# firing on every poll iteration — an unbounded nudge would spam the PR and burn
# vendor quota on a PR CodeRabbit is configured never to review.
run_test "cr_skip_banner_trigger_is_capped" "yes" \
  "$([ "$_cr_trigger_count_1531" -le 4 ] && echo yes || echo no)"
unset _cr_trigger_count_1531

rm -rf "$_cr_mock_dir_1531"
unset _cr_mock_dir_1531 _cr_call_log_1531 actual_output _CR_SKIP_BANNER_1531

# --- Stale draft banner must not shadow a newer, more specific outcome --------
# A repository that runs coderabbit in on_ready.github keeps auto_review.drafts
# false, so EVERY PR collects a "Review skipped / Draft detected" banner while it
# is still a draft. That banner is newer than the HEAD commit, so a guard that
# matched any banner inside the since_iso window would blame it for every later
# ready-phase timeout. Here the newest CodeRabbit comment is a rate-limit notice:
# the run must escalate as rate_limit_max_retries, not review_skipped_banner.
_cr_mock_dir_1531b="$(mktemp -d)"
_cr_call_log_1531b="$_cr_mock_dir_1531b/calls.log"
cat > "$_cr_mock_dir_1531b/gh" <<'CR_GH_1531B'
#!/usr/bin/env bash
# Strict mock: every gh invocation run_coderabbit_review legitimately makes is
# enumerated, and anything else is a hard error. A permissive "*) echo []" fallback
# would let these cases pass for the wrong reason — a renamed or dropped comments
# request would silently return an empty array and still produce the expected
# REASON, proving nothing.
printf '%s\n' "$*" >> "$CR_CALL_LOG"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'abc1531bsha\n'; exit 0 ;;
  *"commits/abc1531bsha --jq .commit.committer.date"*) printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1531bsha/statuses"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '%s\n' '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:01Z","updated_at":"2020-01-01T00:00:01Z","body":"<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!IMPORTANT]\n> ## Review skipped\n>\n> Draft detected."},{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:05:00Z","updated_at":"2020-01-01T00:05:00Z","body":"Review limit reached — rate limit in effect."}]'
    exit 0 ;;
  *"api graphql"*)
    printf '%s\n' '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}'
    exit 0 ;;
  *"pr comment 42"*) exit 0 ;;
  *)
    printf 'UNEXPECTED gh invocation in 1531B mock: %s\n' "$*" >&2
    exit 1 ;;
esac
CR_GH_1531B
chmod +x "$_cr_mock_dir_1531b/gh"

actual_output="$(
  PATH="$_cr_mock_dir_1531b:$PATH" CR_CALL_LOG="$_cr_call_log_1531b" \
    CODERABBIT_NO_TRIGGER_TIMEOUT=1 CODERABBIT_RATE_LIMIT_WAIT=1 CODERABBIT_RATE_LIMIT_MIN_WAIT=1 \
    CODERABBIT_RATE_LIMIT_MAX_RETRIES=1 \
    run_coderabbit_review "42" "fix/42-test" "1" "3" 2>/dev/null || true
)"

run_test "cr_stale_draft_banner_does_not_shadow_rate_limit" "REASON=rate_limit_max_retries" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "cr_stale_draft_banner_still_escalates" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "cr_stale_draft_banner_queried_issue_comments" "yes" \
  "$([ "$(grep_count_or_zero "issues/42/comments" "$_cr_call_log_1531b")" -ge 1 ] && echo yes || echo no)"

rm -rf "$_cr_mock_dir_1531b"
unset _cr_mock_dir_1531b _cr_call_log_1531b actual_output

# --- A banner from a PREVIOUS HEAD must not be attributed to this one --------
# Mirror of the stale-draft case above. Here the only CodeRabbit comment is a
# skip banner that PREDATES the HEAD commit — the shape produced by pushing a
# new commit after a draft-phase banner. CodeRabbit has said nothing about the
# current HEAD, so the outcome is "did not review this HEAD" (no_review), not a
# configuration problem. Reporting review_skipped_banner here would send the
# operator to .coderabbit.yaml for what is really a silent or rate-limited review.
_cr_mock_dir_1531c="$(mktemp -d)"
_cr_call_log_1531c="$_cr_mock_dir_1531c/calls.log"
cat > "$_cr_mock_dir_1531c/gh" <<'CR_GH_1531C'
#!/usr/bin/env bash
# Strict mock: every gh invocation run_coderabbit_review legitimately makes is
# enumerated, and anything else is a hard error. A permissive "*) echo []" fallback
# would let these cases pass for the wrong reason — a renamed or dropped comments
# request would silently return an empty array and still produce the expected
# REASON, proving nothing.
printf '%s\n' "$*" >> "$CR_CALL_LOG"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'abc1531csha\n'; exit 0 ;;
  *"commits/abc1531csha --jq .commit.committer.date"*) printf '2020-01-02T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1531csha/statuses"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '%s\n' '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:01Z","updated_at":"2020-01-01T00:00:01Z","body":"<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!IMPORTANT]\n> ## Review skipped\n>\n> Draft detected."}]'
    exit 0 ;;
  *"api graphql"*)
    printf '%s\n' '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}'
    exit 0 ;;
  *"pr comment 42"*) exit 0 ;;
  *)
    printf 'UNEXPECTED gh invocation in 1531C mock: %s\n' "$*" >&2
    exit 1 ;;
esac
CR_GH_1531C
chmod +x "$_cr_mock_dir_1531c/gh"

actual_output="$(
  PATH="$_cr_mock_dir_1531c:$PATH" CR_CALL_LOG="$_cr_call_log_1531c" \
    CODERABBIT_NO_TRIGGER_TIMEOUT=1 \
    CODERABBIT_RATE_LIMIT_WAIT=1 CODERABBIT_RATE_LIMIT_MIN_WAIT=1 \
    run_coderabbit_review "42" "fix/42-test" "1" "3" 2>/dev/null || true
)"

run_test "cr_banner_from_previous_head_not_attributed" "REASON=no_review" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "cr_banner_from_previous_head_queried_issue_comments" "yes" \
  "$([ "$(grep_count_or_zero "issues/42/comments" "$_cr_call_log_1531c")" -ge 1 ] && echo yes || echo no)"

rm -rf "$_cr_mock_dir_1531c"
unset _cr_mock_dir_1531c _cr_call_log_1531c actual_output

# --- The "latest" comment is ordered by EFFECTIVE event time -----------------
# Admitting comments on `updated_at` and then ordering them on `created_at`
# contradicts itself: an older comment CodeRabbit edited a moment ago is the most
# recent thing it said, but a created_at sort ranks anything posted in between
# above it. Both permutations below are non-activity comments (a skip banner and
# a rate-limit notice), so both reach the timeout guard, and each one flips its
# verdict if the sort key regresses to created_at.

# Permutation 1 — banner created last, rate-limit notice UPDATED last.
# Effective latest is the rate-limit notice, so this is a quota problem.
_cr_mock_dir_1531d="$(mktemp -d)"
_cr_call_log_1531d="$_cr_mock_dir_1531d/calls.log"
cat > "$_cr_mock_dir_1531d/gh" <<'CR_GH_1531D'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CR_CALL_LOG"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'abc1531dsha\n'; exit 0 ;;
  *"commits/abc1531dsha --jq .commit.committer.date"*) printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1531dsha/statuses"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '%s\n' '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:30Z","updated_at":"2020-01-01T00:00:30Z","body":"<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!IMPORTANT]\n> ## Review skipped\n>\n> Draft detected."},{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:10Z","updated_at":"2020-01-01T00:01:00Z","body":"Review limit reached — rate limit in effect."}]'
    exit 0 ;;
  *"api graphql"*)
    printf '%s\n' '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}'
    exit 0 ;;
  *"pr comment 42"*) exit 0 ;;
  *)
    printf 'UNEXPECTED gh invocation in abc1531d mock: %s\n' "$*" >&2
    exit 1 ;;
esac
CR_GH_1531D
chmod +x "$_cr_mock_dir_1531d/gh"

actual_output="$(
  PATH="$_cr_mock_dir_1531d:$PATH" CR_CALL_LOG="$_cr_call_log_1531d" \
    CODERABBIT_NO_TRIGGER_TIMEOUT=1 CODERABBIT_RATE_LIMIT_WAIT=1 CODERABBIT_RATE_LIMIT_MIN_WAIT=1 \
    CODERABBIT_RATE_LIMIT_MAX_RETRIES=1 \
    run_coderabbit_review "42" "fix/42-test" "1" "3" 2>/dev/null || true
)"
run_test "cr_latest_by_effective_time_prefers_updated_rate_limit" "REASON=rate_limit_max_retries" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
rm -rf "$_cr_mock_dir_1531d"
unset _cr_mock_dir_1531d _cr_call_log_1531d actual_output

# Permutation 2 — rate-limit notice created last, banner UPDATED last.
# Effective latest is the banner, so this is a configuration problem.
_cr_mock_dir_1531e="$(mktemp -d)"
_cr_call_log_1531e="$_cr_mock_dir_1531e/calls.log"
cat > "$_cr_mock_dir_1531e/gh" <<'CR_GH_1531E'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CR_CALL_LOG"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'abc1531esha\n'; exit 0 ;;
  *"commits/abc1531esha --jq .commit.committer.date"*) printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1531esha/statuses"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/comments"*) printf '[]\n'; exit 0 ;;
  *"pulls/42/reviews"*) printf '[]\n'; exit 0 ;;
  *"issues/42/comments"*)
    printf '%s\n' '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:30Z","updated_at":"2020-01-01T00:00:30Z","body":"Review limit reached — rate limit in effect."},{"user":{"login":"coderabbitai[bot]"},"created_at":"2020-01-01T00:00:10Z","updated_at":"2020-01-01T00:01:00Z","body":"<!-- This is an auto-generated comment: skip review by coderabbit.ai -->\n\n> [!IMPORTANT]\n> ## Review skipped\n>\n> Draft detected."}]'
    exit 0 ;;
  *"api graphql"*)
    printf '%s\n' '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}'
    exit 0 ;;
  *"pr comment 42"*) exit 0 ;;
  *)
    printf 'UNEXPECTED gh invocation in abc1531e mock: %s\n' "$*" >&2
    exit 1 ;;
esac
CR_GH_1531E
chmod +x "$_cr_mock_dir_1531e/gh"

actual_output="$(
  PATH="$_cr_mock_dir_1531e:$PATH" CR_CALL_LOG="$_cr_call_log_1531e" \
    CODERABBIT_NO_TRIGGER_TIMEOUT=1 CODERABBIT_RATE_LIMIT_WAIT=1 CODERABBIT_RATE_LIMIT_MIN_WAIT=1 \
    CODERABBIT_RATE_LIMIT_MAX_RETRIES=1 \
    run_coderabbit_review "42" "fix/42-test" "1" "3" 2>/dev/null || true
)"
run_test "cr_latest_by_effective_time_prefers_updated_banner" "REASON=review_skipped_banner" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
rm -rf "$_cr_mock_dir_1531e"
unset _cr_mock_dir_1531e _cr_call_log_1531e actual_output

# --- AC-4: rate-limit tolerance spans an hourly vendor quota reset ------------
# Asserted against the script source: the whole point of the change is that the
# shipped numbers (not just the env overrides) are large enough.
#
# These greps used to target the inline "${VAR:-4}" / "${VAR:-900}" expansions
# inside run_coderabbit_review. Issue #1562 gave the same two numbers a second
# reader — the execution-budget invariant — so they were hoisted to a single
# declaration rather than restated, which is what these now pin.
run_test "cr_rate_limit_default_retries_is_four" "1" \
  "$(grep_count_or_zero 'CODERABBIT_RATE_LIMIT_MAX_RETRIES_DEFAULT=4' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
run_test "cr_rate_limit_default_wait_is_900" "1" \
  "$(grep_count_or_zero 'CODERABBIT_RATE_LIMIT_WAIT_DEFAULT=900' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"
# And the review path must actually consume that declaration, so hoisting the
# numbers out cannot leave the wait reading a stale literal.
run_test "cr_rate_limit_review_path_uses_default_consts" "2" \
  "$(grep_count_or_zero 'CODERABBIT_RATE_LIMIT_MAX_RETRIES:-$CODERABBIT_RATE_LIMIT_MAX_RETRIES_DEFAULT' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"

# ---------------------------------------------------------------------------
# Area 19: post-clean settle window and updated_at activity (issue #1556)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 19: post-clean settle and updated_at activity (#1556) ==="

# --- AC-4: the settle window is configurable, per platform ------------------
run_test "settle_config_defined" "yes" \
  "$(type -t _settle_config_for_platform >/dev/null 2>&1 && echo yes || echo no)"
run_test "settle_default_platform" "180 60 30 0" \
  "$(_settle_config_for_platform pr-agent)"
# CodeRabbit gets a longer window because it is the platform that posts late.
run_test "settle_coderabbit_is_longer" "900 120 60 1" \
  "$(_settle_config_for_platform coderabbit)"
run_test "settle_coderabbit_cli_shares_prefix" "900 120 60 1" \
  "$(_settle_config_for_platform coderabbit-cli)"
run_test "settle_generic_env_override" "180 45 30 0" \
  "$(POST_CLEAN_SETTLE_QUIET=45 _settle_config_for_platform pr-agent)"
run_test "settle_per_platform_env_wins" "900 10 10 1" \
  "$(CODERABBIT_POST_CLEAN_SETTLE_QUIET=10 _settle_config_for_platform coderabbit)"
run_test "settle_per_platform_beats_generic" "900 20 20 1" \
  "$(POST_CLEAN_SETTLE_QUIET=99 CODERABBIT_POST_CLEAN_SETTLE_QUIET=20 \
     _settle_config_for_platform coderabbit)"
run_test "settle_window_override" "300 120 60 1" \
  "$(CODERABBIT_POST_CLEAN_SETTLE_WINDOW=300 _settle_config_for_platform coderabbit)"
# Legacy knob still works so existing callers are not silently retimed.
run_test "settle_legacy_post_clean_wait" "180 5 5 0" \
  "$(POST_CLEAN_WAIT=5 _settle_config_for_platform pr-agent)"
run_test "settle_specific_beats_legacy" "180 45 30 0" \
  "$(POST_CLEAN_WAIT=5 POST_CLEAN_SETTLE_QUIET=45 _settle_config_for_platform pr-agent)"
# A quiet period longer than the window could never be satisfied, which would
# burn the whole window and then report settled without ever having been.
run_test "settle_quiet_clamped_to_window" "60 60 30 0" \
  "$(POST_CLEAN_SETTLE_WINDOW=60 POST_CLEAN_SETTLE_QUIET=999 _settle_config_for_platform pr-agent)"
run_test "settle_junk_falls_back_to_default" "180 60 30 0" \
  "$(POST_CLEAN_SETTLE_QUIET=abc _settle_config_for_platform pr-agent)"
run_test "settle_negative_junk_falls_back" "180 60 30 0" \
  "$(POST_CLEAN_SETTLE_QUIET=-5 _settle_config_for_platform pr-agent)"

# --- AC-2 / AC-3: an in-place edit registers as activity --------------------
run_test "activity_probe_defined" "yes" \
  "$(type -t _bot_activity_since >/dev/null 2>&1 && echo yes || echo no)"

_1556_bin="$(mktemp -d)"
_1556_mkgh() {
  # $1 = issue-comments JSON body for the mock to return
  cat > "$_1556_bin/gh" <<GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"issues/42/comments"*) cat <<'JSON'
$1
JSON
    ;;
  *"pulls/42/comments"*) printf '[]\n' ;;
  *"pulls/42/reviews"*)  printf '[]\n' ;;
  *) printf '[]\n' ;;
esac
GHEOF
  chmod +x "$_1556_bin/gh"
}

# The PR #1532 shape exactly: the walkthrough comment was CREATED at 23:23,
# before the 23:34 HEAD commit, and EDITED at 23:52 to carry the new review.
# A created_at-only filter cannot see it; that run only survived because
# CodeRabbit also submitted a formal review, matched separately.
_1556_mkgh '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2026-01-01T23:23:00Z","updated_at":"2026-01-01T23:52:00Z","body":"walkthrough"}]'
run_test "activity_1532_shape_edit_counts" "1" \
  "$(PATH="$_1556_bin:$PATH" _bot_activity_since owner/repo 42 "2026-01-01T23:34:00Z" coderabbitai)"

# The same comment with no edit must NOT count — otherwise every historical
# comment would look like fresh activity and the quiet timer could never expire.
_1556_mkgh '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2026-01-01T23:23:00Z","updated_at":"2026-01-01T23:23:00Z","body":"walkthrough"}]'
run_test "activity_stale_comment_does_not_count" "0" \
  "$(PATH="$_1556_bin:$PATH" _bot_activity_since owner/repo 42 "2026-01-01T23:34:00Z" coderabbitai)"

# A genuinely new comment counts through created_at, as before.
_1556_mkgh '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2026-01-01T23:40:00Z","updated_at":"2026-01-01T23:40:00Z","body":"new"}]'
run_test "activity_new_comment_counts" "1" \
  "$(PATH="$_1556_bin:$PATH" _bot_activity_since owner/repo 42 "2026-01-01T23:34:00Z" coderabbitai)"

# A comment with no updated_at at all must not crash or false-positive.
_1556_mkgh '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2026-01-01T23:23:00Z","body":"no-updated-field"}]'
run_test "activity_missing_updated_at_is_safe" "0" \
  "$(PATH="$_1556_bin:$PATH" _bot_activity_since owner/repo 42 "2026-01-01T23:34:00Z" coderabbitai)"

# Another bot's activity must not satisfy this bot's quiet period.
_1556_mkgh '[{"user":{"login":"some-other-bot[bot]"},"created_at":"2026-01-01T23:40:00Z","updated_at":"2026-01-01T23:40:00Z","body":"unrelated"}]'
run_test "activity_other_bot_ignored" "0" \
  "$(PATH="$_1556_bin:$PATH" _bot_activity_since owner/repo 42 "2026-01-01T23:34:00Z" coderabbitai)"

# A failed query must report -1, never 0 — a broken probe is not silence.
cat > "$_1556_bin/gh" <<'GHFAIL'
#!/usr/bin/env bash
echo "simulated gh failure" >&2
exit 1
GHFAIL
chmod +x "$_1556_bin/gh"
run_test "activity_probe_failure_is_minus_one" "-1" \
  "$(PATH="$_1556_bin:$PATH" _bot_activity_since owner/repo 42 "2026-01-01T23:34:00Z" coderabbitai)"

rm -rf "$_1556_bin"
unset _1556_bin

# --- The completion signal: silence is not the same as finished -------------
#
# Measured on PR #1573, which is what forced this design. HEAD landed at
# 00:17:29; CodeRabbit posted its WALKTHROUGH comment 48s later at 00:18:17,
# and the loop read that as "reviewed, no findings" and returned clean. The
# actual review was submitted at 00:30:32 — twelve minutes after the
# walkthrough — carrying three findings. A quiet period cannot catch that:
# CodeRabbit was silent for the entire window because it was still working.
run_test "settle_coderabbit_requires_submitted_review" "1" \
  "$(_settle_config_for_platform coderabbit | awk '{print $4}')"
run_test "settle_other_platforms_do_not_require_review" "0" \
  "$(_settle_config_for_platform pr-agent | awk '{print $4}')"
run_test "settle_require_review_overridable" "0" \
  "$(CODERABBIT_POST_CLEAN_REQUIRE_REVIEW=0 _settle_config_for_platform coderabbit | awk '{print $4}')"

# A platform name reaches this function from --platform and from the workflow
# config, neither validated upstream, and was interpolated into an eval. I could
# not craft a working exploit — the uppercase transform breaks the obvious
# vectors — but eval on config-derived data is not a construct worth keeping.
run_test "settle_hostile_platform_name_is_safe" "180 60 30 0" \
  "$(_settle_config_for_platform 'a}">/tmp/settle-probe;${b')"
run_test "settle_hostile_platform_no_side_effect" "absent" \
  "$(rm -f /tmp/settle-probe; _settle_config_for_platform 'a}">/tmp/settle-probe;${b' >/dev/null 2>&1; \
     [ -e /tmp/settle-probe ] && echo present || echo absent)"
# An unusable prefix must degrade to the generic knobs, not discard them.
run_test "settle_hostile_name_still_honours_generic" "180 42 30 0" \
  "$(POST_CLEAN_SETTLE_QUIET=42 _settle_config_for_platform 'we!rd')"
run_test "settle_no_eval_in_lookup" "0" \
  "$(grep_count_or_zero 'eval "v=' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh")"

run_test "review_probe_defined" "yes" \
  "$(type -t _bot_review_submitted_since >/dev/null 2>&1 && echo yes || echo no)"
run_test "review_substantive_helper_defined" "yes" \
  "$(type -t _review_body_is_substantive >/dev/null 2>&1 && echo yes || echo no)"
run_test "review_substantive_helper_rejects_ack_punctuation" "no" \
  "$(_review_body_is_substantive "Thanks!" && echo yes || echo no)"

_1556_rbin="$(mktemp -d)"
_1556_mkreviews() {
  cat > "$_1556_rbin/gh" <<GHEOF
#!/usr/bin/env bash
case "\$*" in
  *"pulls/42/reviews"*) cat <<'JSON'
$1
JSON
    ;;
  *) printf '[]\n' ;;
esac
GHEOF
  chmod +x "$_1556_rbin/gh"
}

# A walkthrough comment is NOT a submitted review — this is the whole point.
_1556_mkreviews '[]'
run_test "review_probe_no_review_is_zero" "0" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" coderabbitai)"

# The PR #1573 review, submitted 13 minutes after HEAD.
_1556_mkreviews '[{"user":{"login":"coderabbitai[bot]"},"submitted_at":"2026-08-22T00:30:32Z","state":"COMMENTED","commit_id":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","body":"Actionable comments posted: 3"}]'
run_test "review_probe_detects_submitted_review" "1" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" coderabbitai)"
run_test "review_probe_detects_submitted_review_for_head" "1" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef coderabbitai)"

# GitHub may omit commit_id. Missing commit metadata is still acceptable, but
# an explicit different commit must not satisfy the current-head settle.
_1556_mkreviews '[{"user":{"login":"coderabbitai[bot]"},"submitted_at":"2026-08-22T00:30:32Z","state":"COMMENTED","commit_id":null,"body":"Actionable comments posted: 3"}]'
run_test "review_probe_detects_submitted_review_for_head_without_commit_id" "1" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef coderabbitai)"

# Empty-body review containers are produced when the bot replies inside
# existing review threads. They are not a review of the current code.
_1556_mkreviews '[{"user":{"login":"coderabbitai[bot]"},"submitted_at":"2026-08-22T00:30:32Z","state":"COMMENTED","commit_id":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","body":""}]'
run_test "review_probe_empty_body_container_is_zero" "0" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef coderabbitai)"

# A substantive review plus later empty containers still satisfies the settle.
_1556_mkreviews '[{"user":{"login":"coderabbitai[bot]"},"submitted_at":"2026-08-22T00:30:32Z","state":"COMMENTED","commit_id":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","body":"Actionable comments posted: 3"},{"user":{"login":"coderabbitai[bot]"},"submitted_at":"2026-08-22T00:33:22Z","state":"COMMENTED","commit_id":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","body":""}]'
run_test "review_probe_substantive_plus_container_is_one" "1" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef coderabbitai)"

# Empty containers on a different head must not satisfy this head.
_1556_mkreviews '[{"user":{"login":"coderabbitai[bot]"},"submitted_at":"2026-08-22T00:30:32Z","state":"COMMENTED","commit_id":"feedfacefeedfacefeedfacefeedfacefeedface","body":""}]'
run_test "review_probe_other_head_container_is_zero" "0" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef coderabbitai)"

# A review from a PREVIOUS head must not satisfy this head.
_1556_mkreviews '[{"user":{"login":"coderabbitai[bot]"},"submitted_at":"2026-08-22T00:10:00Z","state":"COMMENTED","body":"Actionable comments posted: 3"}]'
run_test "review_probe_ignores_stale_review" "0" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" coderabbitai)"

# Another bot's review must not satisfy this bot.
_1556_mkreviews '[{"user":{"login":"other-bot[bot]"},"submitted_at":"2026-08-22T00:30:32Z","state":"COMMENTED","body":"Actionable comments posted: 3"}]'
run_test "review_probe_ignores_other_bot" "0" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" coderabbitai)"

cat > "$_1556_rbin/gh" <<'GHFAIL2'
#!/usr/bin/env bash
echo "simulated failure" >&2; exit 1
GHFAIL2
chmod +x "$_1556_rbin/gh"
run_test "review_probe_failure_is_minus_one" "-1" \
  "$(PATH="$_1556_rbin:$PATH" _bot_review_submitted_since owner/repo 42 "2026-08-22T00:17:29Z" coderabbitai)"
rm -rf "$_1556_rbin"
unset _1556_rbin

# --- AC-1: the loop owns the wait, and the contract says so -----------------
_1556_loop="$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
# The activity probe inside run_coderabbit_review must accept updated_at too;
# that was the specific created_at-only filter reported on PR #1532.
# Asserted as "present", not "appears exactly once": the rate-limit comment
# selector adopted the same created_at-or-updated_at filter for the same
# reason (CodeRabbit edits a comment in place rather than posting a new one),
# so a fixed count here would fail on a correct change elsewhere in the file.
run_test "coderabbit_activity_probe_accepts_updated_at" "yes" \
  "$([ "$(grep_count_or_zero '(.created_at > $since or (.updated_at // .created_at) > $since)' "$_1556_loop")" -ge 1 ] && echo yes || echo no)"
# The verdict must no longer be a single fixed sleep.
run_test "post_clean_no_longer_single_wait" "0" \
  "$(grep_count_or_zero '_interruptible_sleep "$post_clean_wait"' "$_1556_loop")"
run_test "post_clean_emits_settled_field" "yes" \
  "$(grep -q 'print_kv POST_CLEAN_SETTLED ' "$_1556_loop" && echo yes || echo no)"
run_test "post_clean_emits_settled_at" "yes" \
  "$(grep -q 'print_kv POST_CLEAN_SETTLED_AT ' "$_1556_loop" && echo yes || echo no)"
# An exhausted window must be distinguishable from a genuinely quiet one.
run_test "post_clean_reports_timeout_distinctly" "yes" \
  "$(grep -q 'print_kv POST_CLEAN_SETTLE_TIMEOUT 1' "$_1556_loop" && echo yes || echo no)"
# A failed activity probe must never be counted as silence.
run_test "post_clean_probe_failure_not_silence" "yes" \
  "$(grep -q 'not counting this interval as quiet' "$_1556_loop" && echo yes || echo no)"
# Silence before the review lands must not accumulate toward the quiet period.
run_test "post_clean_gates_quiet_on_review" "yes" \
  "$(grep -q 'quiet period starts now' "$_1556_loop" && echo yes || echo no)"
run_test "post_clean_reports_missing_review" "yes" \
  "$(grep -q 'print_kv POST_CLEAN_NO_SUBMITTED_REVIEW 1' "$_1556_loop" && echo yes || echo no)"
run_test "post_clean_anchors_since_to_head_commit" "yes" \
  "$(grep -q 'settle_head_iso=' "$_1556_loop" && echo yes || echo no)"
# The anchor must be the pre-dispatch head, never commits/HEAD: the API
# resolves HEAD to the default branch, which on PR #1575 was nine days old,
# so any past review satisfied the require-review settle (issue #1574).
run_test "post_clean_anchor_uses_pre_dispatch_head" "yes" \
  "$(grep -q 'commits/${loop_head_sha}' "$_1556_loop" && echo yes || echo no)"
run_test "post_clean_anchor_never_commits_HEAD" "0" \
  "$(grep_count_or_zero 'commits/${head_sha:-HEAD}' "$_1556_loop")"
# The documented knobs must actually appear in --help (AC-4).
for _knob in POST_CLEAN_SETTLE_QUIET POST_CLEAN_SETTLE_WINDOW POST_CLEAN_POLL; do
  run_test "help_documents_$_knob" "yes" \
    "$(grep -q "$_knob=<" "$_1556_loop" && echo yes || echo no)"
done
unset _knob _1556_loop

# ---------------------------------------------------------------------------
# Area 20: the late-thread re-check is one contract, owned by the loop (#1574)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 20: late-thread re-check contract (#1574) ==="

_1574_loop="$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
_1574_p91="$REPO_ROOT/docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"
_1574_p92="$REPO_ROOT/docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md"

# The --help text carried 600/180 for CodeRabbit while the code used 900/120.
# Read both and compare, so the numbers cannot drift apart again.
read -r _1574_cw _1574_cq _ _ <<<"$(_settle_config_for_platform coderabbit)"
_1574_help="$(bash "$_1574_loop" --help 2>&1 || true)"
run_test "help_window_default_matches_code" "$_1574_cw" \
  "$(printf '%s\n' "$_1574_help" | grep -oE 'Maximum total time to spend settling \(default: [0-9]+' | grep -oE '[0-9]+$')"
run_test "help_quiet_default_matches_code" "$_1574_cq" \
  "$(printf '%s\n' "$_1574_help" | grep -oE 'Defaults per platform: [0-9]+ for coderabbit' | grep -oE '[0-9]+')"

# A skipped recheck must say why, so the checklist can tell "nothing could
# arrive late" from "settling was suppressed".
run_test "recheck_skip_reason_emitted" "yes" \
  "$(grep -q 'print_kv POST_CLEAN_RECHECK_SKIP_REASON' "$_1574_loop" && echo yes || echo no)"
for _reason in not_clean compare_mode skip_env no_thread_posting_platforms no_pr_number; do
  run_test "recheck_skip_reason_$_reason" "yes" \
    "$(grep -q "POST_CLEAN_RECHECK_SKIP_REASON $_reason" "$_1574_loop" && echo yes || echo no)"
done
run_test "help_documents_skip_reason" "yes" \
  "$(grep -q 'POST_CLEAN_RECHECK_SKIP_REASON=' <<< "$_1574_help" && echo yes || echo no)"

# Captured help with trailing data larger than a pipe buffer must keep both
# matching and absent-text assertions reliable under pipefail (#1877).
_1877_padding="$(printf '%*s' 1048576 '')"
_1877_large_help="$_1574_help
$_1877_padding"
run_test "help_large_output_early_match" "yes" \
  "$(grep -Fq 'POST_CLEAN_RECHECK_SKIP_REASON=' <<< "$_1877_large_help" && echo yes || echo no)"
run_test "help_large_output_absent_text" "no" \
  "$(grep -Fq '__1877_ABSENT_HELP_TOKEN__' <<< "$_1877_large_help" && echo yes || echo no)"
run_test "help_large_output_window_default" "$_1574_cw" \
  "$(grep -oE 'Maximum total time to spend settling \(default: [0-9]+' <<< "$_1877_large_help" | grep -oE '[0-9]+$')"
run_test "help_large_output_quiet_default" "$_1574_cq" \
  "$(grep -oE 'Defaults per platform: [0-9]+ for coderabbit' <<< "$_1877_large_help" | grep -oE '[0-9]+')"
unset _1877_padding _1877_large_help

# Protocol 91 must defer to the loop's settle fields rather than carry a wait
# of its own (AC-2), and Protocols 91/92 must describe one contract (AC-3).
run_test "p91_has_no_fixed_recheck_sleep" "0" \
  "$(grep_count_or_zero 'sleep 10' "$_1574_p91")"
# Both clean paths — settled and no-thread-platforms — emit the head binding,
# and the head is read before any reviewer is dispatched, then compared after.
run_test "loop_emits_head_sha_on_both_clean_paths" "2" \
  "$(grep_count_or_zero 'print_kv POST_CLEAN_HEAD_SHA' "$_1574_loop")"
run_test "loop_reads_head_before_dispatch" "yes" \
  "$(awk '/^loop_head_sha=""/{h=NR} /^aggregate_result="skipped"/{a=NR} END{exit !(h>0 && a>0 && h>a)}' "$_1574_loop" && echo yes || echo no)"
run_test "loop_refuses_head_moved_during_run" "yes" \
  "$(grep -q 'aggregate_reason="head_moved_during_run"' "$_1574_loop" && echo yes || echo no)"
run_test "p91_names_head_moved_during_run" "yes" \
  "$(grep -q 'head_moved_during_run' "$_1574_p91" && echo yes || echo no)"
# A head that moved during a clean run is a re-run, not a fixer cycle: the
# ledger does not count it and neither cap fires on it.
_1574_ledger_body="$(jq -nc '{schema:"reviewer_loop_history.v1",pr_number:42,history_status:"available",entries:[
  {iteration:1,head_sha:"a1",run_id:"r1",result:"needs_fixes",reason:"head_moved_during_run"},
  {iteration:2,head_sha:"a2",run_id:"r1",result:"needs_fixes",reason:"unresolved_review_threads"}]}' \
  | { printf '%s\n' "$REVIEWER_LOOP_HISTORY_MARKER" '```json'; cat; printf '```\n'; })"
run_test "ledger_excludes_head_moved_reruns" "1 1 available" \
  "$(reviewer_loop_history_entries_count "$_1574_ledger_body" r1)"
run_test "cap_skipped_for_head_moved" "yes" \
  "$(grep -q 'if \[ "\$aggregate_reason" = "head_moved_during_run" \]; then' "$_1574_loop" && echo yes || echo no)"
# The head is re-validated in Check 4 BEFORE the helper invocation (there is
# no label-present/absent branch any more — the helper runs unconditionally,
# PR #1818 F1 round 10) and a stale existing label is pulled back.
run_test "p91_revalidates_head_before_label" "yes" \
  "$(awk '/^# Check 4:/{p=1} p && /SETTLE_APPLIES:-1}" -eq 1 \] && ! settle_head_ok/{found=1} p && /if ! \.\/scripts\/development-workflow\/apply-readiness-labels\.sh/{ if (found) ok=1 } END{exit !ok}' "$_1574_p91" && echo yes || echo no)"
run_test "p91_pulls_stale_label_back" "yes" \
  "$(grep -q 'it covers a head that is no longer the PR head' "$_1574_p91" && echo yes || echo no)"
# A head-move rerun never escalates on a failed ledger persist: no fixer is
# dispatched, so there is nothing for the ledger to bound.
run_test "persist_failure_ignores_head_moved" "1" \
  "$(reviewer_loop_persist_failure_should_escalate 1 needs_fixes head_moved_during_run; echo $?)"
run_test "persist_failure_still_escalates_real_needs_fixes" "0" \
  "$(reviewer_loop_persist_failure_should_escalate 1 needs_fixes unresolved_review_threads; echo $?)"
run_test "p91_step7_snippet_fails_fast" "yes" \
  "$(awk '/^set -euo pipefail$/{s=NR} /^# Drop settle telemetry from any earlier invocation first/{ if (s==NR-1) ok=1 } END{exit !ok}' "$_1574_p91" && echo yes || echo no)"
unset _1574_ledger_body
for _field in POST_CLEAN_SETTLED POST_CLEAN_SETTLE_TIMEOUT POST_CLEAN_NO_SUBMITTED_REVIEW POST_CLEAN_SETTLED_AT POST_CLEAN_RECHECK_SKIP_REASON POST_CLEAN_HEAD_SHA; do
  run_test "p91_consumes_$_field" "yes" \
    "$(grep -q "$_field" "$_1574_p91" && echo yes || echo no)"
  run_test "p92_names_$_field" "yes" \
    "$(grep -q "$_field" "$_1574_p92" && echo yes || echo no)"
done
# AC-4: an unsettled clean verdict without a submitted review is refused before
# the label, not merely discouraged after it.
run_test "p91_checklist_refuses_no_submitted_review" "yes" \
  "$(grep -q 'POST_CLEAN_NO_SUBMITTED_REVIEW:-0}" = "1"' "$_1574_p91" && echo yes || echo no)"
# Stale telemetry from a previous invocation must never survive into Check 0.6:
# the Step 7 block clears POST_CLEAN_* before the loop runs and exports nothing
# when the loop exits non-zero.
run_test "p91_step7_clears_stale_settle_vars" "yes" \
  "$(grep -q "grep -oE '^(POST_CLEAN|LOCAL_AI)_\[A-Z_\]\*'" "$_1574_p91" && echo yes || echo no)"
run_test "p91_step7_exports_only_on_zero_exit" "yes" \
  "$(grep -q 'Do not enter Step 8a on this run' "$_1574_p91" && echo yes || echo no)"
# Protocol 91 carries no wait at all any more: the only sleep in 8a.1 was the
# fixed one this issue removes, and the timeout path now goes back to Step 7.
run_test "p91_8a1_has_no_sleep" "0" \
  "$(awk '/^### 8a\.1:/,/^## Step 8b/' "$_1574_p91" | grep -cE '^[[:space:]]*sleep ' || true)"


# Execute the gate, not just grep it: extract Check 0.5 + 0.6 from the
# readiness checklist fence and run them with a stubbed gh.
_1574_gate="$(mktemp)"
{
  cat <<'STUB'
set -euo pipefail
PR_NUMBER=42
TARGET_REPO=owner/repo
gh() {
  case "$*" in
    *headRefOid*) printf '%s\n' "${MOCK_HEAD:-}" ;;
    *) printf '%s\n' "${MOCK_SUMMARY:-}" ;;
  esac
}
STUB
  awk '/^# Check 0\.5:/{p=1} /^# Check 1:/{p=0} p' "$_1574_p91"
} > "$_1574_gate"
run_test "gate_extracted_has_check_0_6" "yes" "$(grep -q '^# Check 0.6' "$_1574_gate" && echo yes || echo no)"
# The extracted gate must parse in every shell the fence's contract names;
# the Check 0.5 jq filter had an unterminated quote until this PR.
run_test "gate_parses_in_bash" "yes" "$(bash -n "$_1574_gate" 2>/dev/null && echo yes || echo no)"
run_test "gate_parses_in_zsh" "yes" "$(if command -v zsh >/dev/null 2>&1; then zsh -n "$_1574_gate" 2>/dev/null && echo yes || echo no; else echo yes; fi)"
_1574_clean='### Automated Reviewer Loop Summary

**Result:** clean — no blocking findings'
_1574_skipped='### Automated Reviewer Loop Summary

**Result:** skipped — no review platforms configured'
_1574_head="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
_1574_run_gate() {
  # $@ = VAR=value assignments; prints the exit status
  local status=0
  env -i PATH="$PATH" MOCK_SUMMARY="$_1574_clean" MOCK_HEAD="$_1574_head" \
    LOCAL_AI_CONFIGURED=0 \
    "$@" bash "$_1574_gate" >/dev/null 2>&1 || status=$?
  printf '%s' "$status"
}
run_test "gate_skipped_flag_passes" "0" "$(_1574_run_gate REVIEWER_LOOP_SKIPPED_NO_PLATFORMS=true)"
run_test "gate_skipped_summary_passes" "0" "$(_1574_run_gate MOCK_SUMMARY="$_1574_skipped")"
run_test "gate_missing_fields_refused" "12" "$(_1574_run_gate)"
run_test "gate_no_thread_platforms_passes" "0" "$(_1574_run_gate POST_CLEAN_RECHECK=0 POST_CLEAN_RECHECK_SKIP_REASON=no_thread_posting_platforms POST_CLEAN_HEAD_SHA="$_1574_head")"
# The no-thread path is bound to a head too: a push after Step 7 voids it.
run_test "gate_no_thread_platforms_unbound_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=0 POST_CLEAN_RECHECK_SKIP_REASON=no_thread_posting_platforms)"
run_test "gate_no_thread_platforms_other_head_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=0 POST_CLEAN_RECHECK_SKIP_REASON=no_thread_posting_platforms POST_CLEAN_HEAD_SHA=0123456789012345678901234567890123456789)"
run_test "gate_suppressed_recheck_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=0 POST_CLEAN_RECHECK_SKIP_REASON=skip_env)"
run_test "gate_recheck_without_reason_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=0)"
run_test "gate_settled_passes" "0" "$(_1574_run_gate POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=1 POST_CLEAN_SETTLED_AT=2026-08-22T13:49:18Z POST_CLEAN_HEAD_SHA="$_1574_head")"
run_test "gate_skipped_no_platforms_unset_local_ai_passes" "0" "$(_1574_run_gate REVIEWER_LOOP_SKIPPED_NO_PLATFORMS=true LOCAL_AI_CONFIGURED=)"
run_test "gate_local_ai_unset_refused" "12" "$(_1574_run_gate LOCAL_AI_CONFIGURED= POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=1 POST_CLEAN_SETTLED_AT=2026-08-22T13:49:18Z POST_CLEAN_HEAD_SHA="$_1574_head")"
run_test "gate_local_ai_not_current_refused" "12" "$(_1574_run_gate LOCAL_AI_CONFIGURED=1 LOCAL_AI_HEAD_CURRENT=0 LOCAL_AI_REVIEWED_HEAD="$_1574_head" POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=1 POST_CLEAN_SETTLED_AT=2026-08-22T13:49:18Z POST_CLEAN_HEAD_SHA="$_1574_head")"
run_test "gate_local_ai_current_passes" "0" "$(_1574_run_gate LOCAL_AI_CONFIGURED=1 LOCAL_AI_HEAD_CURRENT=1 LOCAL_AI_REVIEWED_HEAD="$_1574_head" POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=1 POST_CLEAN_SETTLED_AT=2026-08-22T13:49:18Z POST_CLEAN_HEAD_SHA="$_1574_head")"
# A settled verdict is bound to one head: telemetry without a head, or for a
# head the PR has moved past, is refused.
run_test "gate_settled_without_head_binding_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=1)"
run_test "gate_settled_for_other_head_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=1 POST_CLEAN_HEAD_SHA=0123456789012345678901234567890123456789)"
run_test "gate_no_submitted_review_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=0 POST_CLEAN_SETTLE_TIMEOUT=1 POST_CLEAN_NO_SUBMITTED_REVIEW=1)"
run_test "gate_settle_timeout_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=0 POST_CLEAN_SETTLE_TIMEOUT=1)"
run_test "gate_unsettled_without_flags_refused" "12" "$(_1574_run_gate POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=0)"
# Planted violation: invert the settled comparison and the matrix must notice.
_1574_gate_bad="$(mktemp)"
sed 's/POST_CLEAN_SETTLED:-0}" = "1"/POST_CLEAN_SETTLED:-0}" = "0"/' "$_1574_gate" > "$_1574_gate_bad"
_1574_bad_status=0
env -i PATH="$PATH" MOCK_SUMMARY="$_1574_clean" MOCK_HEAD="$_1574_head" POST_CLEAN_RECHECK=1 POST_CLEAN_SETTLED=1 POST_CLEAN_HEAD_SHA="$_1574_head" bash "$_1574_gate_bad" >/dev/null 2>&1 || _1574_bad_status=$?
run_test "gate_planted_inversion_is_caught" "12" "$_1574_bad_status"
rm -f "$_1574_gate" "$_1574_gate_bad"
unset -f _1574_run_gate
unset _1574_gate _1574_gate_bad _1574_clean _1574_skipped _1574_bad_status _1574_head
unset _1574_loop _1574_p91 _1574_p92 _1574_cw _1574_cq _1574_help _reason _field

# ---------------------------------------------------------------------------
# Area 14: CodeRabbit rate-limit window is read from the vendor, not guessed
# (issue #1579)
#
# Two defects, one root cause: the loop decided "CodeRabbit is rate limited"
# from the mere presence of a rate-limit comment after the HEAD commit, and
# sized its wait from a fixed constant. Measured 2026-08-24, the org allowance
# was 1 review/hour while the loop retried 4 x 900 s, so it spent its whole
# budget inside a window that could grant at most one review; and on PR #1575 a
# 21-hour-old rate-limit comment still read as live, suppressing every trigger.
#
# CodeRabbit states its own window ("Next included review available in N
# minutes"). These tests pin both the parse and the staleness decision it
# enables.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 14: CodeRabbit rate-limit window parsing (issue #1579) ==="

_1579_ago() {
  local mins="$1"
  date -u -v-"${mins}"M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -d "${mins} minutes ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
}
_1579_ago_s() {
  local secs="$1"
  date -u -v-"${secs}"S +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -d "${secs} seconds ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
}
_1579_state() {
  if coderabbit_rate_limit_comment_is_current "$1" "$2"; then
    printf 'current\n'
  else
    printf 'stale\n'
  fi
}
# The exact sentence CodeRabbit posted on PR #1590 at 2026-08-24T03:12:02Z.
_1579_window='**Next included review available in 27 minutes.**'
_1579_nowindow='> [!WARNING]
> ## Review limit reached'

# --- wait sizing -----------------------------------------------------------
# 27 minutes + the 30 s boundary buffer. The fixed default (900) is what this
# replaces: it would have retried 12 minutes before the vendor could answer.
run_test "1579_wait_parses_stated_minutes" "1650" "$(coderabbit_rate_limit_wait_seconds "$_1579_window" 900)"
run_test "1579_wait_singular_minute" "90" "$(coderabbit_rate_limit_wait_seconds 'Next included review available in 1 minute.' 900)"
# CodeRabbit's second wording, observed on PR #1588 at 2026-08-24T03:42:56Z
# within the same hour as the first. The extra "will be" is exactly what a
# regex anchored on "review available" cannot span — it silently fell back to
# the 900 s constant instead of the 7 minutes the vendor stated.
run_test "1579_wait_parses_will_be_wording" "450" "$(coderabbit_rate_limit_wait_seconds 'Your next included review will be available in 7 minutes.' 900)"
# The word "included" is what keeps this off unrelated "available in N" prose.
run_test "1579_wait_ignores_unrelated_available_in" "900" "$(coderabbit_rate_limit_wait_seconds 'The maintainer is available in 5 minutes.' 900)"
run_test "1579_wait_seconds_unit" "75" "$(coderabbit_rate_limit_wait_seconds 'next included review available in 45 seconds' 900)"
# Clamped: an unattended run must never park for hours on a vendor string.
run_test "1579_wait_hours_clamped_to_max" "3600" "$(coderabbit_rate_limit_wait_seconds 'Next included review available in 2 hours' 900)"
run_test "1579_wait_absent_phrase_uses_fallback" "900" "$(coderabbit_rate_limit_wait_seconds "$_1579_nowindow" 900)"
run_test "1579_wait_empty_body_uses_fallback" "900" "$(coderabbit_rate_limit_wait_seconds '' 900)"
# Wording drift must degrade to the fallback, never to zero or to an error.
run_test "1579_wait_non_numeric_uses_fallback" "900" "$(coderabbit_rate_limit_wait_seconds 'Next included review available in twelve minutes' 900)"
# "05" must not be read as an octal literal (that aborts the script under set -e).
run_test "1579_wait_leading_zero_not_octal" "330" "$(coderabbit_rate_limit_wait_seconds 'Next included review available in 05 minutes' 900)"
# Seven digits would overflow the multiplication; refuse rather than wrap.
run_test "1579_wait_absurd_value_refused" "900" "$(coderabbit_rate_limit_wait_seconds 'Next included review available in 1000000 minutes' 900)"
run_test "1579_wait_never_zero_for_zero_window" "30" "$(coderabbit_rate_limit_wait_seconds 'Next included review available in 0 minutes' 900)"
run_test "1579_wait_respects_max_override" "100" "$(CODERABBIT_RATE_LIMIT_WAIT_MAX=100 coderabbit_rate_limit_wait_seconds "$_1579_window" 900)"
run_test "1579_wait_respects_buffer_override" "1620" "$(CODERABBIT_RATE_LIMIT_WAIT_BUFFER=0 coderabbit_rate_limit_wait_seconds "$_1579_window" 900)"
# A junk override degrades to the documented default, never to a zero wait
# (a zero wait would busy-spin the retry against the vendor).
run_test "1579_wait_junk_buffer_uses_default" "1650" "$(CODERABBIT_RATE_LIMIT_WAIT_BUFFER=abc coderabbit_rate_limit_wait_seconds "$_1579_window" 900)"
run_test "1579_wait_junk_fallback_arg_uses_default" "900" "$(coderabbit_rate_limit_wait_seconds "$_1579_nowindow" notanumber)"
# PLANTED VIOLATION: a digit-only override with a leading zero and an 8 or 9
# ("008") passes the `*[!0-9]*` check unchanged and is not "junk" by that
# check's definition, but bash reads a leading-zero literal as octal inside
# $((...)) and "008" is not a valid octal literal (8 is not an octal digit) —
# this must not reach that arithmetic unstripped, or it aborts the whole
# script under `set -e` instead of degrading like every other override above.
# Reverting the leading-zero strip on buffer/max_seconds (pr-review-loop.sh,
# coderabbit_rate_limit_wait_seconds) reproduces the crash: manually confirmed
# during review (PR #1592) with `CODERABBIT_RATE_LIMIT_WAIT_BUFFER=008
# coderabbit_rate_limit_wait_seconds` — the process exits nonzero with "008:
# value too great for base" instead of returning a wait.
run_test "1579_wait_buffer_leading_zero_with_8_not_octal" "1628" "$(CODERABBIT_RATE_LIMIT_WAIT_BUFFER=008 coderabbit_rate_limit_wait_seconds "$_1579_window" 900)"
run_test "1579_wait_max_leading_zero_with_8_not_octal" "8" "$(CODERABBIT_RATE_LIMIT_WAIT_MAX=008 coderabbit_rate_limit_wait_seconds "$_1579_window" 900)"

# --- staleness -------------------------------------------------------------
run_test "1579_live_within_stated_window" "current" "$(_1579_state "$_1579_window" "$(_1579_ago 5)")"
run_test "1579_live_just_inside_stated_window" "current" "$(_1579_state "$_1579_window" "$(_1579_ago 26)")"
run_test "1579_spent_past_stated_window" "stale" "$(_1579_state "$_1579_window" "$(_1579_ago 60)")"
# Without a stated window, CODERABBIT_RATE_LIMIT_STALE_AFTER (one vendor hour)
# bounds how long the comment stays believable.
run_test "1579_unstated_window_recent_is_live" "current" "$(_1579_state "$_1579_nowindow" "$(_1579_ago 30)")"
run_test "1579_unstated_window_old_is_spent" "stale" "$(_1579_state "$_1579_nowindow" "$(_1579_ago 90)")"
# The PR #1575 case that motivated the issue: 21 hours later, still "live".
run_test "1579_pr1575_21h_old_comment_is_spent" "stale" "$(_1579_state "$_1579_nowindow" "$(_1579_ago 1260)")"
# Unknown or skewed timestamps degrade to the previous conservative behaviour
# (wait) rather than to spending a review attempt the caller may not have.
run_test "1579_unparseable_timestamp_stays_live" "current" "$(_1579_state "$_1579_window" "not-a-date")"
run_test "1579_empty_timestamp_stays_live" "current" "$(_1579_state "$_1579_window" "")"
run_test "1579_future_timestamp_stays_live" "current" "$(_1579_state "$_1579_window" "2099-01-01T00:00:00Z")"

# --- AC-1: a reply older than this run's own trigger is not an answer ------
# Without this, the loop reads its own pre-trigger evidence as the response to
# the trigger it just posted and reports "rate limited" without ever giving
# CodeRabbit a chance to answer.
run_test "1579_reply_before_this_runs_trigger_is_not_current" "stale" \
  "$(coderabbit_rate_limit_comment_is_current "$_1579_window" "$(_1579_ago 5)" "$(_1579_ago 2)" && printf 'current\n' || printf 'stale\n')"
run_test "1579_reply_after_this_runs_trigger_is_current" "current" \
  "$(coderabbit_rate_limit_comment_is_current "$_1579_window" "$(_1579_ago 2)" "$(_1579_ago 5)" && printf 'current\n' || printf 'stale\n')"
# On a fresh run there is no trigger yet. The anchor must not then discard a
# genuinely live limit — the window rule has to decide alone.
run_test "1579_empty_anchor_falls_back_to_window_rule" "current" \
  "$(coderabbit_rate_limit_comment_is_current "$_1579_window" "$(_1579_ago 5)" "" && printf 'current\n' || printf 'stale\n')"
# Clock skew: the anchor is stamped locally, the timestamp comes from GitHub.
# A reply a few seconds "before" the trigger is still the answer to it. Timestamps
# are computed relative to real "now" (like _1579_ago above), not hardcoded to a
# fixed calendar moment: a hardcoded pair only satisfies the window check in
# coderabbit_rate_limit_comment_is_current while the wall clock is still close to
# whenever the test was written, and silently starts failing once real time moves
# past that window — this was caught live during review (PR #1592).
run_test "1579_anchor_tolerates_small_clock_skew" "current" \
  "$(CODERABBIT_TRIGGER_ANCHOR_SKEW=60 coderabbit_rate_limit_comment_is_current "$_1579_window" "$(_1579_ago_s 300)" "$(_1579_ago_s 270)" && printf 'current\n' || printf 'stale\n')"
# ...but a reply from well before the trigger is not.
run_test "1579_anchor_rejects_large_gap" "stale" \
  "$(CODERABBIT_TRIGGER_ANCHOR_SKEW=60 coderabbit_rate_limit_comment_is_current "$_1579_window" "$(_1579_ago_s 990)" "$(_1579_ago_s 270)" && printf 'current\n' || printf 'stale\n')"
# An unparseable anchor must not silently discard the comment either.
run_test "1579_junk_anchor_falls_back_to_window_rule" "current" \
  "$(coderabbit_rate_limit_comment_is_current "$_1579_window" "$(_1579_ago 5)" "not-a-date" && printf 'current\n' || printf 'stale\n')"
# PLANTED VIOLATION: same octal-literal class as the wait-sizing overrides
# above, on the one operator override in this function that reaches $((...))
# arithmetic. CODERABBIT_TRIGGER_ANCHOR_SKEW=008 passes the digit-only check
# unchanged; "008" is not a valid octal literal, so the anchor-skew arithmetic
# aborts the whole script under `set -e` without the leading-zero strip.
# Manually confirmed during review (PR #1592): reverting the strip on
# anchor_skew reproduces "008: value too great for base" from a comment 5 s
# before the trigger with an 8 s configured skew (created a few seconds
# outside a 0-padded skew window, which used to be within a 60 s skew).
run_test "1579_anchor_skew_leading_zero_with_8_not_octal" "current" \
  "$(CODERABBIT_TRIGGER_ANCHOR_SKEW=008 coderabbit_rate_limit_comment_is_current "$_1579_window" "$(_1579_ago_s 5)" "$(_1579_ago_s 1)" && printf 'current\n' || printf 'stale\n')"

# --- the JSON wrapper both call sites share --------------------------------
_1579_live() {
  if coderabbit_rate_limit_is_live "$1"; then printf 'live\n'; else printf 'not-live\n'; fi
}
run_test "1579_is_live_empty_json_not_live" "not-live" "$(_1579_live '')"
run_test "1579_is_live_recent_window" "live" \
  "$(_1579_live "$(jq -cn --arg b "$_1579_window" --arg c "$(_1579_ago 5)" '{body:$b, created_at:$c}')")"
run_test "1579_is_live_expired_window" "not-live" \
  "$(_1579_live "$(jq -cn --arg b "$_1579_window" --arg c "$(_1579_ago 60)" '{body:$b, created_at:$c}')")"
# Malformed JSON must not read as live — an unparseable object is no evidence
# of a live limit, and reading it as one would re-create the #1579 stall.
run_test "1579_is_live_malformed_json_not_live" "not-live" "$(_1579_live 'not json at all')"

# --- AC-2 / AC-4: the post-rate-limit branch re-checks before posting -------
# "resume" only lifts a paused state; against a rate limit CodeRabbit answers
# "Reviews resumed" and reviews nothing. The branch may post `review` only after
# re-reading the rate-limit state; while that state is live, it must hold.
_1579_loop_src="$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
_1579_rl_branch="$(awk '/no SUCCESS commit status found/,/CodeRabbit did.not review this HEAD/' "$_1579_loop_src")"
run_test "1597_rate_limit_branch_rechecks_after_wait" "yes" \
  "$([ "$(printf '%s' "$_1579_rl_branch" | grep -c 'coderabbit_post_wait_rate_limit_json' || true)" -ge 1 ] && echo yes || echo no)"
run_test "1597_rate_limit_branch_holds_live_window" "yes" \
  "$([ "$(printf '%s' "$_1579_rl_branch" | grep -c 'not posting a trigger while quota refusal remains outstanding' || true)" -ge 1 ] && echo yes || echo no)"
run_test "1597_rate_limit_refusal_refunds_retry_budget" "yes" \
  "$([ "$(grep_count_or_zero 'not counting it toward CODERABBIT_RATE_LIMIT_MAX_RETRIES' "$_1579_loop_src")" -ge 1 ] && echo yes || echo no)"
run_test "1597_held_rate_limit_posts_when_spent" "yes" \
  "$([ "$(grep_count_or_zero 'rate-limit window elapsed after a held wait' "$_1579_loop_src")" -ge 1 ] && echo yes || echo no)"
run_test "1597_held_rate_limit_blocks_silent_preemption" "yes" \
  "$([ "$(grep_count_or_zero 'coderabbit_rate_limit_hold_seen\" -eq 0' "$_1579_loop_src")" -ge 1 ] && echo yes || echo no)"
run_test "1597_review_trigger_posts_clear_held_rate_limit" "3" \
  "$(grep_count_or_zero '^[[:space:]]*coderabbit_rate_limit_hold_seen=0' "$_1579_loop_src")"
run_test "1579_rate_limit_branch_does_not_post_resume" "0" \
  "$(printf '%s' "$_1579_rl_branch" | grep -c -- '--body "@coderabbitai resume"' || true)"
# The extraction must actually have found the branch; an empty window would
# make both counts trivially pass.
run_test "1579_rate_limit_branch_extraction_nonempty" "yes" \
  "$([ -n "$_1579_rl_branch" ] && printf 'yes\n' || printf 'no\n')"

# --- a failed lookup is not an absence of rate limiting ---------------------
# coderabbit_newest_rate_limit_comment previously piped gh straight into jq and
# ended in `|| printf ''`, so a failed API call and "no rate-limit comment"
# were the same answer. Both call sites then posted a fresh review trigger,
# spending from an allowance measured at 1 per hour on evidence never read.
_1579_gh_dir="$(mktemp -d)"
cat > "$_1579_gh_dir/gh" <<'_1579_GH_EOF'
#!/bin/bash
case "${STUB_MODE:-ok}" in
  fail)    echo "gh: API error" >&2; exit 1 ;;
  garbage) printf 'not json at all\n' ;;
  empty)   printf '[]\n' ;;
  *)       printf '[{"user":{"login":"coderabbitai[bot]"},"created_at":"2026-08-24T03:12:02Z","body":"rate limited by coderabbit.ai. Next included review available in 27 minutes."}]\n' ;;
esac
_1579_GH_EOF
chmod +x "$_1579_gh_dir/gh"
_1579_probe() {
  local out st=0
  out="$(PATH="$_1579_gh_dir:$PATH" STUB_MODE="$1" coderabbit_newest_rate_limit_comment owner/repo 1 "coderabbitai[bot]" 2026-08-24T00:00:00Z 2>/dev/null)" || st=$?
  printf '%s\n' "$st"
}
_1579_probe_has_output() {
  local out
  out="$(PATH="$_1579_gh_dir:$PATH" STUB_MODE="$1" coderabbit_newest_rate_limit_comment owner/repo 1 "coderabbitai[bot]" 2026-08-24T00:00:00Z 2>/dev/null)" || true
  if [ -n "$out" ]; then printf 'yes\n'; else printf 'no\n'; fi
}
run_test "1579_lookup_found_status" "0" "$(_1579_probe ok)"
run_test "1579_lookup_found_has_output" "yes" "$(_1579_probe_has_output ok)"
# Success with nothing to report is status 0 and empty — distinct from failure.
run_test "1579_lookup_none_status" "0" "$(_1579_probe empty)"
run_test "1579_lookup_none_has_no_output" "no" "$(_1579_probe_has_output empty)"
# A failed API call must be its own signal, not "no rate limit".
run_test "1579_lookup_gh_failure_status" "2" "$(_1579_probe fail)"
run_test "1579_lookup_unparseable_status" "2" "$(_1579_probe garbage)"
# Caller error is reported as a caller error, not as an API outage. Without
# this, a missing argument builds a malformed endpoint, gh fails, and the
# result is indistinguishable from a real lookup failure.
_1579_argcheck() {
  local st=0
  PATH="$_1579_gh_dir:$PATH" STUB_MODE=empty coderabbit_newest_rate_limit_comment "$@" >/dev/null 2>&1 || st=$?
  printf '%s\n' "$st"
}
run_test "1579_lookup_no_args_status" "2" "$(_1579_argcheck)"
run_test "1579_lookup_too_few_args_status" "2" "$(_1579_argcheck a b c)"
run_test "1579_lookup_too_many_args_status" "2" "$(_1579_argcheck a b c d e)"
run_test "1579_lookup_blank_repo_status" "2" "$(_1579_argcheck '' 1 bot 2026-01-01T00:00:00Z)"
run_test "1579_lookup_blank_since_status" "2" "$(_1579_argcheck owner/repo 1 bot '')"
run_test "1579_lookup_four_valid_args_status" "0" "$(_1579_argcheck owner/repo 1 bot 2026-01-01T00:00:00Z)"
rm -rf "$_1579_gh_dir"
unset -f _1579_probe _1579_probe_has_output _1579_argcheck
unset _1579_gh_dir

# --- remaining window, not the whole window again --------------------------
# coderabbit_rate_limit_wait_seconds returns the FULL announced window, which
# is only correct at the instant the comment appears. Sleeping it again
# part-way through pushes the retry a full extra quota cycle past the moment a
# review becomes available.
# The timestamp is built by one `date` call and the age computed by another, so
# a second boundary between them shifts the result by one. Assert the value is
# within a tolerance of the expectation rather than exactly equal — an exact
# comparison here is a flaky test, not a strict one.
_1579_remaining_near() {
  local age_s="$1" want="$2" tol="${3:-3}"
  local got delta
  got="$(coderabbit_rate_limit_remaining_seconds "$_1579_window" "$(_1579_ago_s "$age_s")" 900)"
  case "$got" in
    '' | *[!0-9]*) printf 'non-numeric:%s\n' "$got"; return 0 ;;
  esac
  delta=$(( got > want ? got - want : want - got ))
  if [ "$delta" -le "$tol" ]; then
    printf 'within\n'
  else
    printf 'got %s want ~%s\n' "$got" "$want"
  fi
}
run_test "1579_remaining_fresh_comment_is_full_window" "within" "$(_1579_remaining_near 0 1650)"
# 27 min window, 26 min elapsed -> ~90s left, not another 1650s.
run_test "1579_remaining_mid_window_subtracts_age" "within" "$(_1579_remaining_near 1560 90)"
run_test "1579_remaining_half_window" "within" "$(_1579_remaining_near 780 870)"
# The tolerance must not be wide enough to hide the bug this pins: sleeping the
# full window when only ~90s remains is a 1560s error, far outside it.
# Assert only that the mismatch branch fired, not the exact computed value:
# that value is clock-derived (89, 90 or 91), so pinning it reintroduces the
# flakiness this whole block exists to remove.
_1579_tolerance_rejects() {
  # Did the near-comparison report a mismatch? Only that, deliberately: the
  # computed value is clock-derived (89, 90 or 91), so asserting it exactly
  # would reintroduce the flakiness this block exists to remove.
  local out
  out="$(_1579_remaining_near "$1" "$2")"
  case "$out" in
    within) printf 'accepted\n' ;;
    *) printf 'rejected\n' ;;
  esac
}
run_test "1579_remaining_tolerance_still_catches_full_window" "rejected" \
  "$(_1579_tolerance_rejects 1560 1650)"
# Past the window, a floor keeps the retry from spinning instantly. This one is
# an exact comparison safely: the floor is a constant, not clock-derived.
run_test "1579_remaining_expired_window_uses_floor" "30" \
  "$(coderabbit_rate_limit_remaining_seconds "$_1579_window" "$(_1579_ago_s 3600)" 900)"
# Age that cannot be computed degrades to the previous behaviour, not to zero.
run_test "1579_remaining_unparseable_created_at" "1650" \
  "$(coderabbit_rate_limit_remaining_seconds "$_1579_window" "not-a-date" 900)"
run_test "1579_remaining_future_created_at" "1650" \
  "$(coderabbit_rate_limit_remaining_seconds "$_1579_window" "2099-01-01T00:00:00Z" 900)"
# Clock-derived like the others above: the fallback is 900 minus the comment's
# age, and a fresh comment's age is 0 or 1 depending on where the two `date`
# reads land. Compared within a tolerance rather than pinned exactly.
_1579_fallback_near() {
  local got delta
  got="$(coderabbit_rate_limit_remaining_seconds "Review rate limited." "$(_1579_ago_s 0)" 900)"
  case "$got" in
    '' | *[!0-9]*) printf 'non-numeric:%s\n' "$got"; return 0 ;;
  esac
  delta=$(( got > 900 ? got - 900 : 900 - got ))
  if [ "$delta" -le 3 ]; then printf 'within\n'; else printf 'got %s want ~900\n' "$got"; fi
}
run_test "1579_remaining_no_stated_window_uses_fallback" "within" "$(_1579_fallback_near)"

# --- the selector must match every observed banner shape -------------------
# Three shapes have been seen and no single marker covers them all. Matching
# only one means a live limit reads as absent, and the loop spends a review
# from a one-per-hour allowance.
_1579_sel() {
  # -R is required: the argument is raw text, not JSON. Without it jq fails to
  # parse and the test silently compares against an empty string.
  printf '%s' "$1" | jq -Rsr 'if test("rate.?limit|review limit reached|next included review"; "i") then "yes" else "no" end' 2>/dev/null
}
run_test "1579_selector_matches_html_marker_shape" "yes" \
  "$(_1579_sel '<!-- rate limited by coderabbit.ai --> Review limit reached')"
run_test "1579_selector_matches_command_refusal_shape" "yes" \
  "$(_1579_sel 'Review rate limited. Your next included review will be available in 7 minutes.')"
# The visible-text-only shape: no HTML marker, no literal "rate limit".
run_test "1579_selector_matches_visible_text_without_marker" "yes" \
  "$(_1579_sel '## Review limit reached
**Next included review available in 27 minutes.**')"
run_test "1579_selector_ignores_ordinary_comment" "no" \
  "$(_1579_sel 'Thanks, looks good to me.')"
unset -f _1579_remaining_near _1579_tolerance_rejects _1579_fallback_near _1579_sel

# --- mutation check --------------------------------------------------------
# The staleness verdicts above must actually depend on the parsed window. Shadow
# the parser with one that always reports a huge window: the 21-hour-old comment
# must then flip to "current". If it does not, the assertions above are passing
# for some reason other than the logic they claim to test.
_1579_real_parser="$(declare -f coderabbit_rate_limit_wait_seconds)"
coderabbit_rate_limit_wait_seconds() { printf '999999\n'; }
run_test "1579_mutation_huge_window_flips_verdict" "current" "$(_1579_state "$_1579_nowindow" "$(_1579_ago 1260)")"
eval "$_1579_real_parser"
# Restored parser must give the real answer again.
run_test "1579_mutation_restored_parser_is_stale" "stale" "$(_1579_state "$_1579_nowindow" "$(_1579_ago 1260)")"

# --- AC-3(a): end-to-end — a stale rate-limit reply must not suppress the
# silent non-trigger retrigger. This is the PR #1575 defect itself: a
# rate-limit comment whose window elapsed 21 hours earlier still read as "CodeRabbit
# is rate limited" and silenced the loop's own proactive "@coderabbitai review"
# nudge. Runs the real run_coderabbit_review poll loop against a scripted `gh`,
# not just the extracted decision functions above, so the wiring between
# coderabbit_rate_limit_is_live and the silent-non-trigger guard is proven, not
# just each side in isolation.
_1579_e2e_mock_dir="$(mktemp -d)"
_1579_e2e_call_log="$_1579_e2e_mock_dir/calls.log"
export _1579_E2E_CALL_LOG="$_1579_e2e_call_log"
export _1579_E2E_STALE_CREATED
_1579_E2E_STALE_CREATED="$(date -u -v-2H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '2 hours ago' +"%Y-%m-%dT%H:%M:%SZ")"
cat > "$_1579_e2e_mock_dir/gh" <<'CR_GH_1579A'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$_1579_E2E_CALL_LOG"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'sha1579a\n'; exit 0 ;;
  *"commits/sha1579a --jq .commit.committer.date"*) printf '2000-01-01T00:00:00Z\n'; exit 0 ;;
  *"pr comment 42"*) exit 0 ;;
  *"issues/42/comments"*)
    printf '[{"user":{"login":"coderabbitai[bot]"},"created_at":"%s","updated_at":"%s","body":"Review rate limited."}]\n' \
      "$_1579_E2E_STALE_CREATED" "$_1579_E2E_STALE_CREATED"
    exit 0 ;;
  *"api graphql"*)
    printf '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}\n'; exit 0 ;;
  *) printf '[]\n'; exit 0 ;;
esac
CR_GH_1579A
chmod +x "$_1579_e2e_mock_dir/gh"

# The wait is bounded even though this path should never take it: the fixture's
# comment is two hours old and therefore spent, so the rate-limit branch is
# skipped. If the staleness logic ever regresses, an unbounded invocation would
# sleep the default wait and the suite would *stall* rather than fail — a
# regression that hangs is harder to diagnose than one that goes red.
# stderr is captured, not discarded: both the silent-non-trigger path and the
# rate-limit retry post the identical `@coderabbitai review` body, so the call
# log alone cannot say which one fired. The two paths log distinct lines, and
# that is what distinguishes them.
_1579_e2e_stderr="$(mktemp)"
PATH="$_1579_e2e_mock_dir:$PATH" \
  CODERABBIT_NO_TRIGGER_TIMEOUT=1 CODERABBIT_RATE_LIMIT_MAX_RETRIES=1 \
  CODERABBIT_RATE_LIMIT_WAIT=1 CODERABBIT_RATE_LIMIT_MIN_WAIT=1 \
  run_coderabbit_review "42" "fix/42-test" "1" "3" >/dev/null 2>"$_1579_e2e_stderr" || true

run_test "1579_stale_reply_does_not_block_silent_retrigger" "yes" \
  "$([ "$(grep_count_or_zero '@coderabbitai review' "$_1579_e2e_call_log")" -ge 1 ] && echo yes || echo no)"
# It must be the SILENT NON-TRIGGER path: a spent rate-limit comment should not
# route the loop through the rate-limit retry at all.
run_test "1579_stale_reply_took_the_silent_non_trigger_path" "yes" \
  "$([ "$(grep_count_or_zero 'silent non-trigger' "$_1579_e2e_stderr")" -ge 1 ] && echo yes || echo no)"
run_test "1579_stale_reply_did_not_take_the_rate_limit_path" "yes" \
  "$([ "$(grep_count_or_zero 'after rate-limit wait' "$_1579_e2e_stderr")" -eq 0 ] && echo yes || echo no)"
# The mock's default case is permissive ("[]" for anything unenumerated), so a
# renamed endpoint could silently return empty and still look clean. Assert the
# comments endpoint that carries the rate-limit reply was actually queried.
run_test "1579_stale_reply_queried_issue_comments" "yes" \
  "$([ "$(grep_count_or_zero 'issues/42/comments' "$_1579_e2e_call_log")" -ge 1 ] && echo yes || echo no)"

rm -rf "$_1579_e2e_mock_dir"
rm -f "$_1579_e2e_stderr"
unset _1579_E2E_CALL_LOG _1579_E2E_STALE_CREATED _1579_e2e_mock_dir _1579_e2e_call_log _1579_e2e_stderr

# --- AC-3(b) / AC-2 / AC-4: end-to-end — a LIVE rate limit is a refusal, not
# a review-attempt retry. Waiting is free; posting while the live quota refusal
# is still outstanding spends the same allowance the loop is waiting on.
_1579_e2e_mock_dir2="$(mktemp -d)"
_1579_e2e_call_log2="$_1579_e2e_mock_dir2/calls.log"
_1579_e2e_stdout2="$_1579_e2e_mock_dir2/stdout.log"
_1579_e2e_stderr2="$_1579_e2e_mock_dir2/stderr.log"
export _1579_E2E_CALL_LOG2="$_1579_e2e_call_log2"
export _1579_E2E_LIVE_CREATED
_1579_E2E_LIVE_CREATED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
cat > "$_1579_e2e_mock_dir2/gh" <<'CR_GH_1579B'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$_1579_E2E_CALL_LOG2"
case "$*" in
  "auth status") exit 0 ;;
  *"repo view"*"nameWithOwner"*) printf 'owner/repo\n'; exit 0 ;;
  *"pulls/42 --jq .head.sha"*) printf 'sha1579b\n'; exit 0 ;;
  *"commits/sha1579b --jq .commit.committer.date"*) printf '2000-01-01T00:00:00Z\n'; exit 0 ;;
  *"pr comment 42"*) exit 0 ;;
  *"issues/42/comments"*)
    printf '[{"user":{"login":"coderabbitai[bot]"},"created_at":"%s","updated_at":"%s","body":"Review rate limited."}]\n' \
      "$_1579_E2E_LIVE_CREATED" "$_1579_E2E_LIVE_CREATED"
    exit 0 ;;
  *"api graphql"*)
    printf '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}\n'; exit 0 ;;
  *) printf '[]\n'; exit 0 ;;
esac
CR_GH_1579B
chmod +x "$_1579_e2e_mock_dir2/gh"

PATH="$_1579_e2e_mock_dir2:$PATH" \
  CODERABBIT_NO_TRIGGER_TIMEOUT=999 CODERABBIT_RATE_LIMIT_MAX_RETRIES=1 CODERABBIT_RATE_LIMIT_WAIT=1 \
  CODERABBIT_RATE_LIMIT_MIN_WAIT=1 \
  run_coderabbit_review "42" "fix/42-test" "1" "3" >"$_1579_e2e_stdout2" 2>"$_1579_e2e_stderr2" || true

# The mock logs "$*", which joins argv with spaces and drops the quoting the
# real gh invocation used. A live rate-limit refusal must not produce either
# trigger verb while it remains live after the wait.
run_test "1597_live_rate_limit_does_not_post_review" "0" \
  "$(grep_count_or_zero 'pr comment 42 --body @coderabbitai review' "$_1579_e2e_call_log2")"
run_test "1597_live_rate_limit_does_not_post_resume" "0" \
  "$(grep_count_or_zero 'pr comment 42 --body @coderabbitai resume' "$_1579_e2e_call_log2")"
run_test "1597_live_rate_limit_reports_zero_attempts" "CODERABBIT_TRIGGER_ATTEMPTS=0" \
  "$(grep '^CODERABBIT_TRIGGER_ATTEMPTS=' "$_1579_e2e_stdout2" | tail -n 1)"
run_test "1597_live_rate_limit_reports_zero_reviews" "CODERABBIT_REVIEWS_RECEIVED=0" \
  "$(grep '^CODERABBIT_REVIEWS_RECEIVED=' "$_1579_e2e_stdout2" | tail -n 1)"
run_test "1597_live_rate_limit_logs_hold_after_wait" "yes" \
  "$([ "$(grep_count_or_zero 'not posting a trigger while quota refusal remains outstanding' "$_1579_e2e_stderr2")" -ge 1 ] && echo yes || echo no)"

rm -rf "$_1579_e2e_mock_dir2"
unset _1579_E2E_CALL_LOG2 _1579_E2E_LIVE_CREATED _1579_e2e_mock_dir2 _1579_e2e_call_log2 _1579_e2e_stdout2 _1579_e2e_stderr2

unset -f _1579_ago _1579_ago_s _1579_state _1579_live
unset _1579_window _1579_nowindow _1579_real_parser _1579_loop_src _1579_rl_branch

# ---------------------------------------------------------------------------
echo "=== Area 1648: reviewer-loop current-head evidence ==="

HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

_sha_a='82d2f3a844a6c0c417f5c55e8a01eebdf343de45'
_sha_b='29c0e9d2541a85c0e335052de42599f485d51a67'
_sha_a_upper='82D2F3A844A6C0C417F5C55E8A01EEBDF343DE45'
_sha_abbrev='82d2f3a'
_sha_39='82d2f3a844a6c0c417f5c55e8a01eebdf343de4'
_sha_41="${_sha_a}0"
_sha_non_hex='82d2f3a844a6c0c417f5c55e8a01eebdf343de4g'
_unknown_head='unknown-1756330000-4821-19342'

run_test "1648_classify_same_sha_current" "current" \
  "$(reviewer_loop_head_evidence_classify "$_sha_a" "$_sha_a")"
run_test "1648_classify_case_insensitive_current" "current" \
  "$(reviewer_loop_head_evidence_classify "$_sha_a_upper" "$_sha_a")"
run_test "1648_classify_mismatch" "not-current|head_mismatch" \
  "$(reviewer_loop_head_evidence_classify "$_sha_a" "$_sha_b")"
run_test "1648_classify_abbreviation" "not-current|unverifiable_reviewed_head" \
  "$(reviewer_loop_head_evidence_classify "$_sha_abbrev" "$_sha_a")"
run_test "1648_classify_39_char" "not-current|unverifiable_reviewed_head" \
  "$(reviewer_loop_head_evidence_classify "$_sha_39" "$_sha_a")"
run_test "1648_classify_41_char" "not-current|unverifiable_reviewed_head" \
  "$(reviewer_loop_head_evidence_classify "$_sha_41" "$_sha_a")"
run_test "1648_classify_non_hex" "not-current|unverifiable_reviewed_head" \
  "$(reviewer_loop_head_evidence_classify "$_sha_non_hex" "$_sha_a")"
run_test "1648_classify_empty_reviewed" "not-reported" \
  "$(reviewer_loop_head_evidence_classify "" "$_sha_a")"
run_test "1648_classify_empty_current" "not-current|unverifiable_current_head" \
  "$(reviewer_loop_head_evidence_classify "$_sha_a" "")"
run_test "1648_classify_unknown_placeholder" "not-current|unverifiable_current_head" \
  "$(reviewer_loop_head_evidence_classify "$_sha_a" "$_unknown_head")"

run_test "1648_full_sha_accepts_40" "0" "$(reviewer_loop_head_evidence_full_sha "$_sha_a"; printf '%s' $?)"
run_test "1648_full_sha_rejects_39" "1" "$(reviewer_loop_head_evidence_full_sha "$_sha_39"; printf '%s' $?)"
run_test "1648_full_sha_rejects_41" "1" "$(reviewer_loop_head_evidence_full_sha "$_sha_41"; printf '%s' $?)"
run_test "1648_full_sha_rejects_abbrev" "1" "$(reviewer_loop_head_evidence_full_sha "$_sha_abbrev"; printf '%s' $?)"
run_test "1648_full_sha_rejects_non_hex" "1" "$(reviewer_loop_head_evidence_full_sha "$_sha_non_hex"; printf '%s' $?)"
run_test "1648_full_sha_rejects_empty" "1" "$(reviewer_loop_head_evidence_full_sha ""; printf '%s' $?)"

_1648_render="$(reviewer_loop_head_evidence_render "$_sha_a" "local-ai-reviewer:$_sha_a" "pr-agent:$_sha_b")"
run_contains "1648_render_has_head_evidence_block" "**Head evidence:**" "$_1648_render"
run_contains "1648_render_current_row" "local-ai-reviewer: reviewed \`${_sha_a}\` — current" "$_1648_render"
run_contains "1648_render_mismatch_row" "pr-agent: reviewed \`${_sha_b}\` — not-current (head_mismatch)" "$_1648_render"

_1648_json="$(reviewer_loop_head_evidence_json "$_sha_a" "local-ai-reviewer:$_sha_a")"
run_test "1648_json_state_current" "current" \
  "$(printf '%s\n' "$_1648_json" | jq -r '.[0].state')"

_1648_legacy_payload='{"schema":"reviewer_loop_history.v1","entries":[{"iteration":1,"head_sha":"abc","result":"clean"}]}'
run_test "1648_legacy_payload_parses" "1" \
  "$(printf '%s\n' "$_1648_legacy_payload" | jq -e '.entries[0].reviewed_heads // [] | length >= 0' >/dev/null && echo 1 || echo 0)"

# Check 0.6b gate (Protocol 91 lines 2758-2771) — planted-violation proof P2/P3
check_066b_local_ai_head() {
  if [ "${REVIEWER_LOOP_SKIPPED_NO_PLATFORMS:-false}" = "true" ]; then
    return 0
  elif [ -z "${LOCAL_AI_CONFIGURED:-}" ]; then
    return 12
  elif [ "$LOCAL_AI_CONFIGURED" = "0" ]; then
    return 0
  elif [ "${LOCAL_AI_HEAD_CURRENT:-__unset__}" != "1" ]; then
    return 12
  else
    return 0
  fi
}

unset LOCAL_AI_CONFIGURED LOCAL_AI_HEAD_CURRENT LOCAL_AI_REVIEWED_HEAD REVIEWER_LOOP_SKIPPED_NO_PLATFORMS 2>/dev/null || true
_1648_check_rc=0
check_066b_local_ai_head || _1648_check_rc=$?
run_test "1648_check_066b_unset_configured" "12" "$_1648_check_rc"

export REVIEWER_LOOP_SKIPPED_NO_PLATFORMS=true
unset LOCAL_AI_CONFIGURED
_1648_check_rc=0
check_066b_local_ai_head || _1648_check_rc=$?
run_test "1648_check_066b_skipped_no_platforms_pass" "0" "$_1648_check_rc"
unset REVIEWER_LOOP_SKIPPED_NO_PLATFORMS

export LOCAL_AI_CONFIGURED=1
export LOCAL_AI_HEAD_CURRENT=
_1648_check_rc=0
check_066b_local_ai_head || _1648_check_rc=$?
run_test "1648_check_066b_missing_head_current" "12" "$_1648_check_rc"

export LOCAL_AI_HEAD_CURRENT=0
_1648_check_rc=0
check_066b_local_ai_head || _1648_check_rc=$?
run_test "1648_check_066b_not_current" "12" "$_1648_check_rc"

export LOCAL_AI_HEAD_CURRENT=1
export LOCAL_AI_REVIEWED_HEAD="$_sha_a"
_1648_check_rc=0
check_066b_local_ai_head || _1648_check_rc=$?
run_test "1648_check_066b_current_pass" "0" "$_1648_check_rc"

export LOCAL_AI_CONFIGURED=0
unset LOCAL_AI_HEAD_CURRENT LOCAL_AI_REVIEWED_HEAD 2>/dev/null || true
_1648_check_rc=0
check_066b_local_ai_head || _1648_check_rc=$?
run_test "1648_check_066b_not_configured_pass" "0" "$_1648_check_rc"

unset LOCAL_AI_CONFIGURED LOCAL_AI_HEAD_CURRENT LOCAL_AI_REVIEWED_HEAD 2>/dev/null || true
unset -f check_066b_local_ai_head 2>/dev/null || true
unset _1648_check_rc

_1648_carry_capture=$'POST_CLEAN_HEAD_SHA=abc\nLOCAL_AI_CONFIGURED=1\nLOCAL_AI_REVIEWED_HEAD=def0123456789012345678901234567890abcd\nLOCAL_AI_HEAD_CURRENT=1\n'
_1648_carry_out="$(mktemp)"
printf '%s\n' "$_1648_carry_capture" > "$_1648_carry_out"
for settle_var in $(env | grep -oE '^(POST_CLEAN|LOCAL_AI)_[A-Z_]*' || true); do
  unset "$settle_var"
done
settle_kv="$(mktemp)"
grep -E '^(POST_CLEAN|LOCAL_AI)_[A-Z_]+=[A-Za-z0-9:_-]*$' "$_1648_carry_out" > "$settle_kv" || true
while IFS='=' read -r key value; do
  export "$key=$value"
done < "$settle_kv"
run_test "1648_carry_forward_configured" "1" "${LOCAL_AI_CONFIGURED:-}"
run_test "1648_carry_forward_head_current" "1" "${LOCAL_AI_HEAD_CURRENT:-}"
for settle_var in $(env | grep -oE '^(POST_CLEAN|LOCAL_AI)_[A-Z_]*' || true); do
  unset "$settle_var"
done
run_test "1648_carry_forward_clears" "empty" \
  "$([ -z "${LOCAL_AI_CONFIGURED:-}" ] && [ -z "${LOCAL_AI_HEAD_CURRENT:-}" ] && printf empty || printf present)"
rm -f "$_1648_carry_out" "$settle_kv"

unset _sha_a _sha_b _sha_a_upper _sha_abbrev _sha_39 _sha_41 _sha_non_hex _unknown_head
unset _1648_render _1648_json _1648_legacy_payload _1648_carry_capture

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
