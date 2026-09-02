#!/usr/bin/env bash
# Dispatch tests for the local AI reviewer pr-review-loop platform.
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/local-ai-reviewer.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

actual="$(bot_login_for_platform local-ai-reviewer)"
run_test "bot_login_for_platform_local_ai_reviewer_empty" "" "$actual"

# The invariant is that the parser surfaces local-ai-reviewer *first* in the
# repository's own draft list — not that the list equals the template default.
# A consumer that syncs this template legitimately configures a different set
# (MOME drops pr-agent), so asserting the literal template list turned a
# successful sync into a red required check (#1631). Read the live config and
# skip when this repository does not run local-ai-reviewer on draft PRs at all.
shared_config_copy="$(mktemp)"
cp "$REPO_ROOT/.ai-dev-workflow.yaml" "$shared_config_copy"
draft_reviewers="$(workflow_config_review_on_draft_github "$shared_config_copy")"
rm -f "$shared_config_copy"

# Here-strings rather than pipes into `grep -q` / `head`: this script runs
# under `set -euo pipefail`, where the reader closing the pipe early kills the
# writer with SIGPIPE and aborts the suite with 141.
if grep -Fxq -- "local-ai-reviewer" <<< "$draft_reviewers"; then
  read -r actual <<< "$draft_reviewers"
  run_test "default_draft_github_reviewers_start_with_local_ai" "local-ai-reviewer" "$actual"
else
  echo "SKIP: default_draft_github_reviewers_start_with_local_ai - local-ai-reviewer is not a configured on_draft.github reviewer in this repository"
fi

_local_ai_dispatch_called=0
run_local_ai_reviewer_review() {
  _local_ai_dispatch_called=1
  print_kv RESULT skipped
  print_kv REASON disabled_by_config
  print_kv COMMENT_COUNT 0
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
}

run_platform_review "local-ai-reviewer" "999" "feature/test" "30" "120" >/dev/null 2>&1 || true
run_test "run_platform_review_routes_to_local_ai_reviewer" "1" "$_local_ai_dispatch_called"

if grep -q 'needs_rerun) print_kv RESULT needs_rerun' "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"; then
  actual="present"
else
  actual="missing"
fi
run_test "local_ai_reviewer_preserves_needs_rerun_mapping" "present" "$actual"

unset -f run_local_ai_reviewer_review

# Issue #1648: LOCAL_AI_* stdout contract for dispatch surfaces
_1648_ancestor_sha='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
_1648_live_sha='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
platforms=(local-ai-reviewer)
platform_reviewed_heads=("local-ai-reviewer:$_1648_ancestor_sha")
loop_head_sha="$_1648_live_sha"
_1648_dispatch_out="$(mktemp)"
reviewer_loop_emit_local_ai_head_evidence_keys > "$_1648_dispatch_out"
run_test "1648_dispatch_stale_local_head_current" "LOCAL_AI_HEAD_CURRENT=0" \
  "$(grep '^LOCAL_AI_HEAD_CURRENT=' "$_1648_dispatch_out")"
run_test "1648_dispatch_stale_local_reviewed_head" "LOCAL_AI_REVIEWED_HEAD=$_1648_ancestor_sha" \
  "$(grep '^LOCAL_AI_REVIEWED_HEAD=' "$_1648_dispatch_out")"

platforms=(pr-agent)
platform_reviewed_heads=()
loop_head_sha="$_1648_live_sha"
reviewer_loop_emit_local_ai_head_evidence_keys > "$_1648_dispatch_out"
run_test "1648_dispatch_not_configured" "LOCAL_AI_CONFIGURED=0" \
  "$(grep '^LOCAL_AI_CONFIGURED=' "$_1648_dispatch_out")"

platforms=(local-ai-reviewer)
platform_reviewed_heads=("local-ai-reviewer:")
loop_head_sha="$_1648_live_sha"
reviewer_loop_emit_local_ai_head_evidence_keys > "$_1648_dispatch_out"
run_test "1648_dispatch_missing_reviewed_head" "LOCAL_AI_HEAD_CURRENT=" \
  "$(grep '^LOCAL_AI_HEAD_CURRENT=' "$_1648_dispatch_out")"
run_test "1648_dispatch_configured_no_head" "LOCAL_AI_CONFIGURED=1" \
  "$(grep '^LOCAL_AI_CONFIGURED=' "$_1648_dispatch_out")"

platforms=(local-ai-reviewer)
platform_reviewed_heads=("local-ai-reviewer:$_1648_live_sha")
loop_head_sha="$_1648_live_sha"
reviewer_loop_emit_local_ai_head_evidence_keys > "$_1648_dispatch_out"
run_test "1648_dispatch_current_head" "LOCAL_AI_HEAD_CURRENT=1" \
  "$(grep '^LOCAL_AI_HEAD_CURRENT=' "$_1648_dispatch_out")"
rm -f "$_1648_dispatch_out"
unset _1648_ancestor_sha _1648_live_sha _1648_dispatch_out platforms platform_reviewed_heads loop_head_sha

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"
