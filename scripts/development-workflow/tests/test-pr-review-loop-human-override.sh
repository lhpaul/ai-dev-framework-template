#!/usr/bin/env bash
# test-pr-review-loop-human-override.sh — pr-review-loop.sh harness: the
# head-bound human override of a local-ai-reviewer verdict (#2116).
# duration: 20
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
# covers: scripts/development-workflow/workflow-lib.sh
# covers: docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md
#
# The pr-review-loop.sh harness is split across suites (#1876) that share
# their preamble through tests/lib/pr-review-loop-harness.sh; see the list in
# test-pr-review-loop.sh. This suite holds the #2116 override areas.
#
# Areas in this suite:
#   Area 2116a: override marker validation (workflow_reviewer_human_override_json)
#   Area 2116b: loop dispatch honors a current-head override
#   Area 2116c: ledger record and summary audit
#   Area 2116d: second local pass before the ready gate
#
# Every case is synthetic: a fake gh on PATH serves fabricated comments and
# permissions. Readiness and completion-check cases live in
# test-apply-readiness-labels.sh and test-item-completion-self-check.sh; the
# PR-Agent verification dead end lives in
# test-pr-review-loop-pr-agent-coderabbit.sh next to its fixtures.
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop-human-override.sh [--area <name>]... [--list-areas]
#
# Exit code: 0 if all tests pass, 1 if any test fails, 2 on a usage error.
#
# Assignments here set pr-review-loop.sh globals that the functions under test
# read. ShellCheck does not follow that source, so they carry SC2034 disables.

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

# Shared synthetic fixture: a fake gh that serves the comments in
# $HO_COMMENTS_FILE, permissions from $HO_PERMS ("login=perm ..."), and the
# PR head from $HO_LIVE_HEAD. HO_COMMENTS_FAIL=1 fails the comments read.
_ho_dir="$(mktemp -d)"
cat >"$_ho_dir/gh" <<'HO_GH'
#!/usr/bin/env bash
case "$*" in
  *"issues/42/comments"*)
    [ "${HO_COMMENTS_FAIL:-0}" != 1 ] || exit 1
    cat "$HO_COMMENTS_FILE"; exit 0 ;;
  *"/collaborators/"*"/permission"*)
    login="$(printf '%s' "$*" | sed -n 's#.*collaborators/\([^/]*\)/permission.*#\1#p')"
    for kv in ${HO_PERMS:-}; do
      [ "${kv%%=*}" = "$login" ] && { printf '%s\n' "${kv#*=}"; exit 0; }
    done
    exit 1 ;;
  "pr view 42 --json headRefOid --jq .headRefOid")
    printf '%s\n' "${HO_LIVE_HEAD:?}"; exit 0 ;;
esac
printf 'unexpected synthetic gh call: %s\n' "$*" >>"$HO_UNEXPECTED_LOG"
exit 1
HO_GH
chmod +x "$_ho_dir/gh"
export HO_UNEXPECTED_LOG="$_ho_dir/unexpected"
export HO_COMMENTS_FILE="$_ho_dir/comments.json"
export WORKFLOW_TARGET_GITHUB_REPO=acme/widgets
_ho_head=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
_ho_old=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
export HO_LIVE_HEAD="$_ho_head"

# _ho_marker_comment <id> <login> <type> <json-payload> [prefix]
_ho_marker_comment() {
  jq -cn --argjson id "$1" --arg login "$2" --arg type "$3" --arg payload "$4" --arg prefix "${5:-}" \
    '{id:$id,user:{login:$login,type:$type},created_at:("2026-01-01T00:00:0" + ($id|tostring) + "Z"),
      html_url:("https://example.test/c/" + ($id|tostring)),
      body:($prefix + "<!-- reviewer-loop-human-override:v1 " + $payload + " -->\nOverride.")}'
}
# _ho_payload <head> [reason] [platform] [by]
_ho_payload() {
  jq -cn --arg head "$1" --arg reason "${2-doctrine gap}" --arg platform "${3:-local-ai-reviewer}" --arg by "${4:-}" \
    '{platform:$platform,head:$head,reason:$reason} + (if $by != "" then {by:$by} else {} end)'
}
# _ho_set_comments <comment-json>... (one page)
_ho_set_comments() {
  printf '%s\n' "$@" | jq -s '[.]' >"$HO_COMMENTS_FILE"
}

# ---------------------------------------------------------------------------
# Area 2116a: override marker validation
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2116a: override marker validation ==="

_ho_check() {
  # _ho_check <name> <expected: by-login|none>
  local out
  if out="$(PATH="$_ho_dir:$PATH" workflow_reviewer_human_override_json acme/widgets 42 "$_ho_head" local-ai-reviewer)"; then
    run_test "2116a_$1" "$2" "$(printf '%s' "$out" | jq -r .by)"
  else
    run_test "2116a_$1" "$2" none
  fi
}
export HO_PERMS='maint=write admin1=admin reader=read'
_ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$_ho_head")")"
_ho_check valid_current_head maint
_ho_out="$(PATH="$_ho_dir:$PATH" workflow_reviewer_human_override_json acme/widgets 42 "$_ho_head" local-ai-reviewer)"
run_test "2116a_valid_records_reason" "doctrine gap" "$(printf '%s' "$_ho_out" | jq -r .reason)"
run_test "2116a_valid_records_head" "$_ho_head" "$(printf '%s' "$_ho_out" | jq -r .head)"
run_test "2116a_valid_records_comment" "https://example.test/c/1" "$(printf '%s' "$_ho_out" | jq -r .comment_url)"
_ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$_ho_old")")"
_ho_check older_head_has_no_effect none
_ho_set_comments "$(_ho_marker_comment 1 reader User "$(_ho_payload "$_ho_head")")"
_ho_check read_only_author_has_no_effect none
_ho_set_comments "$(_ho_marker_comment 1 stranger User "$(_ho_payload "$_ho_head")")"
_ho_check permission_lookup_failure_has_no_effect none
printf '[[]]' >"$HO_COMMENTS_FILE"
_ho_check absent_override none
_ho_set_comments "$(_ho_marker_comment 1 maint Bot "$(_ho_payload "$_ho_head")")"
_ho_check bot_author_has_no_effect none
_ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$_ho_head")" "Quoting: ")"
_ho_check marker_not_opening_comment_has_no_effect none
_ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$_ho_head" "   ")")"
_ho_check blank_reason_has_no_effect none
_ho_set_comments "$(_ho_marker_comment 1 maint User "$(jq -cn --arg head "$_ho_head" '{platform:"local-ai-reviewer",head:$head}')")"
_ho_check missing_reason_has_no_effect none
_ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$_ho_head" "x" pr-agent)")"
_ho_check other_platform_has_no_effect none
_ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$_ho_head" "x" local-ai-reviewer someone-else)")"
_ho_check by_mismatch_has_no_effect none
_ho_set_comments "$(_ho_marker_comment 1 maint User '{not json')"
_ho_check malformed_payload_has_no_effect none
# Newest valid override wins; a newer read-only marker does not displace it.
_ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$_ho_head" "first")")" \
  "$(_ho_marker_comment 2 admin1 User "$(_ho_payload "$_ho_head" "second")")" \
  "$(_ho_marker_comment 3 reader User "$(_ho_payload "$_ho_head" "third")")"
_ho_check newest_trusted_override_wins admin1
_ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$_ho_head" "a <!-- reviewer-loop-history:v1 --> b")")"
run_test "2116a_reason_cannot_open_html_comment" "a ‹!-- reviewer-loop-history:v1 --› b" \
  "$(PATH="$_ho_dir:$PATH" workflow_reviewer_human_override_json acme/widgets 42 "$_ho_head" local-ai-reviewer | jq -r .reason)"
_ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$_ho_head" "see \`\`\`fence\`\`\` here")")"
run_test "2116a_reason_cannot_open_code_fence" "see '''fence''' here" \
  "$(PATH="$_ho_dir:$PATH" workflow_reviewer_human_override_json acme/widgets 42 "$_ho_head" local-ai-reviewer | jq -r .reason)"
_ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$_ho_head")")"
run_test "2116a_comments_read_failure_fails_closed" 1 \
  "$(HO_COMMENTS_FAIL=1 PATH="$_ho_dir:$PATH" workflow_reviewer_human_override_json acme/widgets 42 "$_ho_head" local-ai-reviewer >/dev/null 2>&1; echo $?)"
run_test "2116a_short_head_refused" 1 \
  "$(PATH="$_ho_dir:$PATH" workflow_reviewer_human_override_json acme/widgets 42 aaaa local-ai-reviewer >/dev/null 2>&1; echo $?)"
unset -f _ho_check
unset _ho_out

echo "=== Area 2116a complete ==="

# ---------------------------------------------------------------------------
# Area 2116b: loop dispatch honors a current-head override
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2116b: loop dispatch honors a current-head override ==="

# The synthetic local reviewer records each dispatch and reports a finding,
# the situation a human overrides.
_ho_dispatch_case() (
  # _ho_dispatch_case <payload-head> <perms>
  export HO_PERMS="$2"
  if [ -n "$1" ]; then
    _ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$1")")"
  else
    printf '[[]]' >"$HO_COMMENTS_FILE"
  fi
  : >"$_ho_dir/dispatch"
  run_local_ai_reviewer_review() {
    printf 'dispatch\n' >>"$_ho_dir/dispatch"
    printf 'RESULT=needs_fixes\nREASON=findings\nBLOCKING_COUNT=1\nREVIEWED_HEAD=%s\n' "$loop_head_sha"
    return 1
  }
  # shellcheck disable=SC2034 # Read by run_platform_review's override check.
  loop_head_sha="$_ho_head"
  set +e
  out="$(PATH="$_ho_dir:$PATH" run_platform_review local-ai-reviewer 42 fix/2116-test 1 1 2>/dev/null)"
  status=$?
  set -e
  printf 'STATUS=%s\nDISPATCHES=%s\n%s\n' "$status" "$(wc -l <"$_ho_dir/dispatch" | tr -d ' ')" "$out"
)
_ho_out="$(_ho_dispatch_case "$_ho_head" 'maint=write')"
run_test "2116b_valid_override_result_skipped" skipped "$(kv_value_default RESULT "$_ho_out" missing)"
run_test "2116b_valid_override_reason" human_override "$(kv_value_default REASON "$_ho_out" missing)"
run_test "2116b_valid_override_reviewer_not_run" 0 "$(kv_value_default DISPATCHES "$_ho_out" missing)"
run_test "2116b_valid_override_status_zero" 0 "$(kv_value_default STATUS "$_ho_out" missing)"
run_test "2116b_valid_override_reports_head" "$_ho_head" "$(kv_value_default REVIEWED_HEAD "$_ho_out" missing)"
run_test "2116b_valid_override_reports_author" maint "$(kv_value_default HUMAN_OVERRIDE_BY "$_ho_out" missing)"
run_test "2116b_valid_override_reports_reason" "doctrine gap" "$(kv_value_default HUMAN_OVERRIDE_REASON "$_ho_out" missing)"
run_test "2116b_valid_override_no_blocking" 0 "$(kv_value_default BLOCKING_COUNT "$_ho_out" missing)"
for _ho_case in older_head read_only absent; do
  case "$_ho_case" in
    older_head) _ho_out="$(_ho_dispatch_case "$_ho_old" 'maint=write')" ;;
    read_only) _ho_out="$(_ho_dispatch_case "$_ho_head" 'maint=read')" ;;
    absent) _ho_out="$(_ho_dispatch_case "" 'maint=write')" ;;
  esac
  run_test "2116b_${_ho_case}_reviewer_runs" 1 "$(kv_value_default DISPATCHES "$_ho_out" missing)"
  run_test "2116b_${_ho_case}_finding_stands" needs_fixes "$(kv_value_default RESULT "$_ho_out" missing)"
  run_test "2116b_${_ho_case}_status_kept" 1 "$(kv_value_default STATUS "$_ho_out" missing)"
done
unset -f _ho_dispatch_case
unset _ho_case _ho_out

echo "=== Area 2116b complete ==="

# ---------------------------------------------------------------------------
# Area 2116c: ledger record and summary audit
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2116c: ledger record and summary audit ==="

# Feed the real override output through the real platform processor, as the
# main loop does, and read back the ledger record and the summary section.
# shellcheck disable=SC2034 # Production processor consumes the initialized globals.
_ho_processor_case() (
  export HO_PERMS='maint=write'
  _ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$_ho_head")")"
  loop_head_sha="$_ho_head"
  phase_after_clean_enabled=0
  compare_mode=0
  aggregate_result=clean
  aggregate_reason=""
  aggregate_output=""
  aggregate_status=0
  total_comment_count=0
  total_blocking_count=0
  total_suggestion_count=0
  reviewer_failed_required=0
  aggregate_advisory_labels=""
  platform_result_records=()
  platform_reviewed_heads=()
  platform_peer_evidence=()
  platform_result_tokens=()
  platform_blocking_outputs=()
  aggregate_blocking_paths=()
  aggregate_blocking_findings=()
  platform_policy_status_notes=()
  compare_verdicts=()
  human_override_records=()
  local out
  out="$(PATH="$_ho_dir:$PATH" reviewer_loop_local_ai_human_override_output 42 fix/2116-test 2>/dev/null)"
  PATH="$_ho_dir:$PATH" reviewer_loop_process_platform_output local-ai-reviewer 2 "$out" 0 1 >/dev/null
  jq -cn --arg aggregate "$aggregate_result" \
    --argjson records "$(printf '%s\n' ${platform_result_records[@]+"${platform_result_records[@]}"} | jq -s '.')" \
    --argjson heads "$(reviewer_loop_head_evidence_json "$loop_head_sha" ${platform_reviewed_heads[@]+"${platform_reviewed_heads[@]}"})" \
    --arg tokens "${platform_result_tokens[*]}" \
    --arg summary "$(reviewer_loop_human_override_summary_section ${human_override_records[@]+"${human_override_records[@]}"} ${human_override_records[@]+"${human_override_records[@]}"})" \
    '{aggregate:$aggregate,records:$records,heads:$heads,tokens:$tokens,summary:$summary}'
)
_ho_entry="$(_ho_processor_case)"
_ho_record="$(printf '%s' "$_ho_entry" | jq -c '.records[] | select(.platform == "local-ai-reviewer")')"
run_test "2116c_ledger_result_skipped" skipped "$(printf '%s' "$_ho_record" | jq -r .result)"
run_test "2116c_ledger_raw_reason" human_override "$(printf '%s' "$_ho_record" | jq -r .raw_reason)"
run_test "2116c_ledger_records_who" maint "$(printf '%s' "$_ho_record" | jq -r .human_override.by)"
run_test "2116c_ledger_records_head" "$_ho_head" "$(printf '%s' "$_ho_record" | jq -r .human_override.head)"
run_test "2116c_ledger_records_reason" "doctrine gap" "$(printf '%s' "$_ho_record" | jq -r .human_override.reason)"
run_test "2116c_ledger_reviewed_head_is_override_head" "$_ho_head" \
  "$(printf '%s' "$_ho_entry" | jq -r '.heads[] | select(.platform == "local-ai-reviewer") | .reviewed_head')"
run_test "2116c_skip_keeps_clean_aggregate" clean "$(printf '%s' "$_ho_entry" | jq -r .aggregate)"
run_test "2116c_platform_token_names_override" "local-ai-reviewer:skipped (human override by maint)" \
  "$(printf '%s' "$_ho_entry" | jq -r .tokens)"
_ho_summary="$(printf '%s' "$_ho_entry" | jq -r .summary)"
run_test "2116c_summary_has_heading" 1 "$(grep -c '^\*\*Human override:\*\*$' <<<"$_ho_summary")"
run_test "2116c_summary_line_deduplicated" 1 "$(grep -c "^- \`local-ai-reviewer\` skipped on head \`$_ho_head\` by \`maint\`: doctrine gap (\[override comment\](https://example.test/c/1))$" <<<"$_ho_summary")"
run_test "2116c_summary_notes_rearm" 1 "$(grep -c 'A new push re-arms it.' <<<"$_ho_summary")"
run_test "2116c_summary_empty_without_records" "" "$(reviewer_loop_human_override_summary_section)"
unset -f _ho_processor_case
unset _ho_entry _ho_record _ho_summary

echo "=== Area 2116c complete ==="

# ---------------------------------------------------------------------------
# Area 2116d: second local pass before the ready gate
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2116d: second local pass before the ready gate ==="

# The local reviewer already failed on this head (the case a human
# overrides). Without an override the pass is refused as failed_for_head;
# with a current-head override it proceeds to the ready gate without running
# the reviewer.
# shellcheck disable=SC2034 # Production gate consumes the initialized globals.
_ho_second_pass_case() (
  export HO_PERMS='maint=write'
  if [ "$1" = override ]; then
    _ho_set_comments "$(_ho_marker_comment 1 maint User "$(_ho_payload "$_ho_head")")"
  else
    printf '[[]]' >"$HO_COMMENTS_FILE"
  fi
  : >"$_ho_dir/dispatch"
  run_local_ai_reviewer_review() { printf 'dispatch\n' >>"$_ho_dir/dispatch"; printf 'RESULT=needs_fixes\n'; return 1; }
  reviewer_loop_prior_history_payload_from_pr() {
    jq -cn --arg head "$_ho_head" '{schema:"reviewer_loop_history.v1",entries:[{iteration:1,result:"needs_fixes",
      local_second_pass_failed_head:$head,classification_head:$head,
      platform_results:[{platform:"local-ai-reviewer",result:"needs_fixes",raw_result:"needs_fixes",raw_reason:"findings"}],
      reviewed_heads:[{platform:"local-ai-reviewer",reviewed_head:$head}]}]}'
  }
  reviewer_loop_repo_configured_platforms() { printf 'pr-agent\nlocal-ai-reviewer\n'; }
  loop_head_sha="$_ho_head"
  retry_local_review_head=""
  local_review_retry_head_record=""
  phase_after_clean_enabled=1
  branch_name=fix/2116-test
  platforms=(pr-agent local-ai-reviewer)
  compare_mode=0
  aggregate_result=clean
  aggregate_reason=""
  aggregate_output=""
  aggregate_status=0
  total_comment_count=0
  total_blocking_count=0
  total_suggestion_count=0
  reviewer_failed_required=0
  aggregate_advisory_labels=""
  platform_result_records=()
  platform_reviewed_heads=()
  platform_peer_evidence=()
  platform_result_tokens=()
  platform_blocking_outputs=()
  aggregate_blocking_paths=()
  aggregate_blocking_findings=()
  platform_policy_status_notes=()
  compare_verdicts=()
  human_override_records=()
  local_second_pass=0
  local_second_pass_result=""
  # The gate re-enables errexit internally, so capture its status the way
  # production does (in a conditional), not with a set +e window.
  status=0
  PATH="$_ho_dir:$PATH" reviewer_loop_second_local_pass_before_ready_gate 42 >/dev/null 2>&1 || status=$?
  # shellcheck disable=SC2154 # Set by the sourced production gate.
  printf 'STATUS=%s\nREASON=%s\nAGGREGATE=%s\nAGGREGATE_REASON=%s\nDISPATCHES=%s\nRECORDS=%s\n' \
    "$status" "$local_second_pass_reason" "$aggregate_result" "$aggregate_reason" \
    "$(wc -l <"$_ho_dir/dispatch" | tr -d ' ')" "${#human_override_records[@]}"
)
_ho_out="$(_ho_second_pass_case override)"
run_test "2116d_override_proceeds_to_ready_gate" 0 "$(kv_value_default STATUS "$_ho_out" missing)"
run_test "2116d_override_pass_reason" human_override "$(kv_value_default REASON "$_ho_out" missing)"
run_test "2116d_override_keeps_clean" clean "$(kv_value_default AGGREGATE "$_ho_out" missing)"
run_test "2116d_override_reviewer_not_run" 0 "$(kv_value_default DISPATCHES "$_ho_out" missing)"
run_test "2116d_override_recorded_for_summary" 1 "$(kv_value_default RECORDS "$_ho_out" missing)"
_ho_out="$(_ho_second_pass_case absent)"
run_test "2116d_absent_override_refused" 1 "$(kv_value_default STATUS "$_ho_out" missing)"
run_test "2116d_absent_override_failed_for_head" failed_for_head "$(kv_value_default AGGREGATE_REASON "$_ho_out" missing)"
run_test "2116d_absent_override_escalates" escalate "$(kv_value_default AGGREGATE "$_ho_out" missing)"
# The live head moved after the override was posted: the old marker no longer
# names the live head, so the pass is not waved through.
_ho_out="$(HO_LIVE_HEAD="$_ho_old" _ho_second_pass_case override)"
run_test "2116d_override_live_head_moved_refused" 1 "$(kv_value_default STATUS "$_ho_out" missing)"
run_test "2116d_override_live_head_moved_reason" head_moved_during_run "$(kv_value_default AGGREGATE_REASON "$_ho_out" missing)"
unset -f _ho_second_pass_case
unset _ho_out

run_test "2116_fixture_has_no_unexpected_gh_calls" absent "$([ -e "$HO_UNEXPECTED_LOG" ] && printf present || printf absent)"
[ ! -e "$HO_UNEXPECTED_LOG" ] || cat "$HO_UNEXPECTED_LOG" >&2

echo "=== Area 2116d complete ==="

rm -rf "$_ho_dir"
unset -f _ho_marker_comment _ho_payload _ho_set_comments
unset _ho_dir _ho_head _ho_old HO_UNEXPECTED_LOG HO_COMMENTS_FILE HO_PERMS HO_LIVE_HEAD WORKFLOW_TARGET_GITHUB_REPO

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
