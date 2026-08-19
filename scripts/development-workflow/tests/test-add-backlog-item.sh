#!/usr/bin/env bash
# test-add-backlog-item.sh — Unit tests for add-backlog-item.sh create flow.
#
# Exercises issue #965's Priority/Size field updates, and issue #1501's fix
# for the inverted Medium/Normal priority alias (the board has no "Normal"
# option; "Medium" is the real board value):
#   1. Malformed gh output warns and skips project field updates
#   2. Non-numeric issue number in URL warns and skips project field updates
#   3. Happy path: URL parsed, board membership checked, Priority defaults to Medium
#   4. --priority flag: uses supplied value instead of the Medium default
#   5. --size flag: triggers Size field update
#   6. No --size: Size field update is not called
#   7. --type flag: triggers Type field update
#   8. A priority value that does not resolve against the board's actual
#      Priority options (issue #1501) is a hard error: create exits non-zero
#      and no mutation is sent.
#
# Usage: bash scripts/development-workflow/tests/test-add-backlog-item.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
SCRIPT="$REPO_ROOT/scripts/development-workflow/add-backlog-item.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/calls.log"
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

# _config_backup is set before the linear test section overwrites
# .ai-dev-workflow.yaml; cleanup restores it on any exit (including set -e).
_config_backup=""
_config_file="$REPO_ROOT/.ai-dev-workflow.yaml"

cleanup() {
  # Restore .ai-dev-workflow.yaml if it was swapped out by the linear tests.
  # The guard ([ -f "$_config_backup" ]) ensures cp is only called when the
  # backup was successfully created; do not suppress errors — a restore failure
  # means the workspace is clobbered and the test runner must know.
  if [ -n "$_config_backup" ] && [ -f "$_config_backup" ]; then
    cp "$_config_backup" "$_config_file"
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"
case "$*" in
  "auth status")
    exit 0
    ;;
  "repo view --json owner --jq .owner.login")
    printf 'lhpaul\n'
    ;;
  "repo view --json name --jq .name")
    printf 'test-repo\n'
    ;;
  issue\ create\ *)
    case "${MOCK_GH_ISSUE_CREATE_MODE:-ok}" in
      malformed)   printf 'not-a-url\n' ;;
      nonnumeric)  printf 'https://github.com/lhpaul/test-repo/issues/not-a-number\n' ;;
      *)           printf 'https://github.com/lhpaul/test-repo/issues/123\n' ;;
    esac
    ;;
  "project item-add "*)
    printf 'PVTI_added\n'
    ;;
  *"api graphql"*)
    case "$*" in
      *"projectV2(number:"*)
        printf '{"data":{"user":{"projectV2":{"id":"PVT_project_1"}},"organization":null}}\n'
        ;;
      *"projectItems(first:"*)
        printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_item_123","project":{"id":"PVT_project_1","number":1},"status":{"name":"Backlog"},"type":{"name":"Feature"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}\n'
        ;;
      *"fields(first:"*)
        case "${MOCK_PRIORITY_FIELD_MODE:-medium}" in
          normal_only)
            # Simulates a downstream board still configured per the
            # framework's pre-#1501 docs: Urgent, High, Normal, Low — no
            # "Medium" option (issue #1501 code review, "Preserve
            # compatibility with Normal-priority boards").
            printf '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_priority","name":"Priority","options":[{"id":"OPT_urgent","name":"Urgent"},{"id":"OPT_high","name":"High"},{"id":"OPT_normal","name":"Normal"},{"id":"OPT_low","name":"Low"}]},{"id":"PVTSSF_size","name":"Size","options":[{"id":"OPT_size_xs","name":"XS"},{"id":"OPT_size_s","name":"S"},{"id":"OPT_size_m","name":"M"},{"id":"OPT_size_l","name":"L"},{"id":"OPT_size_xl","name":"XL"}]},{"id":"PVTSSF_type","name":"Type","options":[{"id":"OPT_type_feature","name":"Feature"},{"id":"OPT_type_bug","name":"Bug"},{"id":"OPT_type_refactor","name":"Refactor"},{"id":"OPT_type_workflow","name":"Workflow"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}\n'
            ;;
          neither)
            # Simulates a board using an entirely different Priority
            # vocabulary (neither "Medium" nor "Normal" present).
            printf '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_priority","name":"Priority","options":[{"id":"OPT_p0","name":"P0"},{"id":"OPT_p1","name":"P1"}]},{"id":"PVTSSF_size","name":"Size","options":[{"id":"OPT_size_xs","name":"XS"},{"id":"OPT_size_s","name":"S"},{"id":"OPT_size_m","name":"M"},{"id":"OPT_size_l","name":"L"},{"id":"OPT_size_xl","name":"XL"}]},{"id":"PVTSSF_type","name":"Type","options":[{"id":"OPT_type_feature","name":"Feature"},{"id":"OPT_type_bug","name":"Bug"},{"id":"OPT_type_refactor","name":"Refactor"},{"id":"OPT_type_workflow","name":"Workflow"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}\n'
            ;;
          *)
            # Matches the real board's Priority options verified on issue
            # #1501: Urgent, High, Medium, Low — there is no "Normal" option.
            printf '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_priority","name":"Priority","options":[{"id":"OPT_urgent","name":"Urgent"},{"id":"OPT_high","name":"High"},{"id":"OPT_medium","name":"Medium"},{"id":"OPT_low","name":"Low"}]},{"id":"PVTSSF_size","name":"Size","options":[{"id":"OPT_size_xs","name":"XS"},{"id":"OPT_size_s","name":"S"},{"id":"OPT_size_m","name":"M"},{"id":"OPT_size_l","name":"L"},{"id":"OPT_size_xl","name":"XL"}]},{"id":"PVTSSF_type","name":"Type","options":[{"id":"OPT_type_feature","name":"Feature"},{"id":"OPT_type_bug","name":"Bug"},{"id":"OPT_type_refactor","name":"Refactor"},{"id":"OPT_type_workflow","name":"Workflow"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}\n'
            ;;
        esac
        ;;
      *"updateProjectV2ItemFieldValue"*)
        if [ "${MOCK_PRIORITY_UPDATE_MODE:-ok}" = "fail" ]; then
          printf 'transient GraphQL write failure\n' >&2
          exit 42
        fi
        printf '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"PVTI_item_123"}}}}\n'
        ;;
      *)
        printf '{}\n'
        ;;
    esac
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"

export PATH="$MOCK_BIN:$PATH"
export MOCK_GH_CALL_LOG="$CALL_LOG"
export GITHUB_PROJECT_NUMBER="1"
export GITHUB_PROJECT_OWNER="lhpaul"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name — expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

reset_log() { : > "$CALL_LOG"; }

count_log_matches() {
  local pattern="$1"
  awk -v p="$pattern" '$0 ~ p { c++ } END { print c+0 }' "$CALL_LOG"
}

run_create() {
  local mode="${1:-ok}"; shift
  reset_log
  local exit_code=0
  set +e
  MOCK_GH_ISSUE_CREATE_MODE="$mode" \
    "$SCRIPT" create "$@" \
    >"$TMP_ROOT/stdout.log" \
    2>"$TMP_ROOT/stderr.log"
  exit_code=$?
  set -e
  printf '%s' "$exit_code" >"$TMP_ROOT/exit.log"
}

get_stdout() { cat "$TMP_ROOT/stdout.log" 2>/dev/null || true; }
get_stderr() { cat "$TMP_ROOT/stderr.log" 2>/dev/null || true; }
get_exit()   { cat "$TMP_ROOT/exit.log" 2>/dev/null || true; }

echo ""
echo "=== create: URL parsing — malformed gh output ==="

run_create "malformed" --title "Test" --body "body"
run_test "malformed_url_exits_zero" "0" "$(get_exit)"
malformed_stderr="$(get_stderr)"
case "$malformed_stderr" in
  *"Warning: could not extract a numeric issue number"*) malformed_warn="warned" ;;
  *) malformed_warn="$malformed_stderr" ;;
esac
run_test "malformed_url_warns" "warned" "$malformed_warn"
run_test "malformed_url_skips_board_check" "0" "$(count_log_matches 'projectItems')"
run_test "malformed_url_skips_priority_update" "0" "$(count_log_matches 'updateProjectV2ItemFieldValue')"

echo ""
echo "=== create: URL parsing — non-numeric issue number ==="

run_create "nonnumeric" --title "Test" --body "body"
run_test "nonnumeric_exits_zero" "0" "$(get_exit)"
nonnumeric_stderr="$(get_stderr)"
case "$nonnumeric_stderr" in
  *"Warning: could not extract a numeric issue number"*) nonnumeric_warn="warned" ;;
  *) nonnumeric_warn="$nonnumeric_stderr" ;;
esac
run_test "nonnumeric_warns" "warned" "$nonnumeric_warn"
run_test "nonnumeric_skips_board_check" "0" "$(count_log_matches 'projectItems')"
run_test "nonnumeric_skips_priority_update" "0" "$(count_log_matches 'updateProjectV2ItemFieldValue')"

echo ""
echo "=== create: happy path — issue URL in output, Priority defaults to Medium ==="

run_create "ok" --title "Test" --body "body"
run_test "happy_path_exits_zero" "0" "$(get_exit)"
happy_stdout="$(get_stdout)"
case "$happy_stdout" in
  *"https://github.com/lhpaul/test-repo/issues/123"*) url_in_output="yes" ;;
  *) url_in_output="no" ;;
esac
run_test "happy_path_prints_issue_url" "yes" "$url_in_output"
board_check_count="$(count_log_matches 'projectItems')"
run_test "happy_path_checks_board_membership" "yes" "$([ "$board_check_count" -ge 1 ] && echo yes || echo no)"
run_test "happy_path_updates_priority" "1" "$(count_log_matches 'fieldId=PVTSSF_priority')"
# Regression for issue #1501: the requested (defaulted) priority must
# actually be present on the board item afterward — assert the mutation was
# sent with the Medium option ID, not the non-existent "Normal" option.
run_test "happy_path_default_priority_is_medium" "1" "$(count_log_matches 'optionId=OPT_medium')"
run_test "happy_path_skips_size_update" "0" "$(count_log_matches 'fieldId=PVTSSF_size')"

echo ""
echo "=== create: --priority flag overrides Medium default ==="

run_create "ok" --title "Test" --body "body" --priority "High"
run_test "explicit_priority_exits_zero" "0" "$(get_exit)"
# Regression for issue #1501: an explicitly requested priority must actually
# be applied — assert the mutation carries the requested option ID.
run_test "explicit_priority_high_used" "1" "$(count_log_matches 'optionId=OPT_high')"
run_test "explicit_priority_not_medium" "0" "$(count_log_matches 'optionId=OPT_medium')"

echo ""
echo "=== create: Medium priority resolves directly (no Normal alias) ==="

run_create "ok" --title "Test" --body "body" --priority "Medium"
run_test "medium_priority_exits_zero" "0" "$(get_exit)"
run_test "medium_priority_uses_medium_option" "1" "$(count_log_matches 'optionId=OPT_medium')"

echo ""
echo "=== create: unresolvable priority is a hard error, and blocks BEFORE issue creation (issue #1501 code review) ==="

run_create "ok" --title "Test" --body "body" --priority "NoSuchPriority"
run_test "unresolvable_priority_exits_nonzero" "yes" "$([ "$(get_exit)" -ne 0 ] && echo yes || echo no)"
run_test "unresolvable_priority_sends_no_mutation" "0" "$(count_log_matches 'updateProjectV2ItemFieldValue')"
# Regression for the codex-github review finding on this PR: validating the
# priority value BEFORE calling `gh issue create` means an invalid value can
# never leave behind a created-but-unlabeled issue that a blind exit-code
# retry would duplicate.
run_test "unresolvable_priority_skips_issue_create" "0" "$(count_log_matches 'issue create')"
unresolvable_stderr="$(get_stderr)"
case "$unresolvable_stderr" in
  *"Error:"*"could not resolve 'Priority' option 'NoSuchPriority'"*"no issue was created"*) unresolvable_error_result="errored" ;;
  *) unresolvable_error_result="$unresolvable_stderr" ;;
esac
run_test "unresolvable_priority_prints_error" "errored" "$unresolvable_error_result"

echo ""
echo "=== create: default priority adapts to a Normal-only board (issue #1501 code review) ==="

export MOCK_PRIORITY_FIELD_MODE=normal_only
run_create "ok" --title "Test" --body "body"
unset MOCK_PRIORITY_FIELD_MODE
run_test "normal_only_board_default_exits_zero" "0" "$(get_exit)"
run_test "normal_only_board_default_creates_issue" "1" "$(count_log_matches 'issue create')"
run_test "normal_only_board_default_uses_normal_option" "1" "$(count_log_matches 'optionId=OPT_normal')"
run_test "normal_only_board_default_avoids_medium_option" "0" "$(count_log_matches 'optionId=OPT_medium')"

echo ""
echo "=== create: default priority left unset on a board with neither Medium nor Normal (issue #1501 code review) ==="

export MOCK_PRIORITY_FIELD_MODE=neither
run_create "ok" --title "Test" --body "body"
unset MOCK_PRIORITY_FIELD_MODE
# The unresolvable-default case must NOT block issue creation the way an
# unresolvable EXPLICIT --priority does — Priority is simply left unset,
# the same way an omitted --size or --type is left unset.
run_test "neither_board_default_exits_zero" "0" "$(get_exit)"
run_test "neither_board_default_creates_issue" "1" "$(count_log_matches 'issue create')"
run_test "neither_board_default_sends_no_priority_mutation" "0" "$(count_log_matches 'fieldId=PVTSSF_priority')"

echo ""
echo "=== create: post-creation Priority failure is a distinct partial-success exit, not a generic failure (issue #1501 code review) ==="

export MOCK_PRIORITY_UPDATE_MODE=fail
run_create "ok" --title "Test" --body "body"
unset MOCK_PRIORITY_UPDATE_MODE
partial_stdout="$(get_stdout)"
partial_stderr="$(get_stderr)"
run_test "partial_success_exit_code_is_five" "5" "$(get_exit)"
# The issue WAS created — its URL must still be visible on stdout, and
# `gh issue create` must have actually run (not been skipped), proving this
# is a genuine partial success rather than the pre-flight blocking path.
run_test "partial_success_creates_issue" "1" "$(count_log_matches 'issue create')"
case "$partial_stdout" in
  *"https://github.com/lhpaul/test-repo/issues/123"*) partial_url_result="printed" ;;
  *) partial_url_result="$partial_stdout" ;;
esac
run_test "partial_success_prints_issue_url" "printed" "$partial_url_result"
case "$partial_stderr" in
  *"already created"*"Do NOT retry issue creation"*) partial_message_result="explicit" ;;
  *) partial_message_result="$partial_stderr" ;;
esac
run_test "partial_success_prints_explicit_no_retry_message" "explicit" "$partial_message_result"

echo ""
echo "=== create: --size flag updates Size field ==="

run_create "ok" --title "Test" --body "body" --size "M"
run_test "size_flag_exits_zero" "0" "$(get_exit)"
run_test "size_flag_updates_size_field" "1" "$(count_log_matches 'fieldId=PVTSSF_size')"
run_test "size_flag_uses_m_option" "1" "$(count_log_matches 'optionId=OPT_size_m')"
run_test "size_flag_also_updates_priority" "1" "$(count_log_matches 'fieldId=PVTSSF_priority')"

echo ""
echo "=== create: --type flag updates Type field ==="

run_create "ok" --title "Test" --body "body" --type "Workflow"
run_test "type_flag_exits_zero" "0" "$(get_exit)"
run_test "type_flag_updates_type_field" "1" "$(count_log_matches 'fieldId=PVTSSF_type')"
run_test "type_flag_uses_workflow_option" "1" "$(count_log_matches 'optionId=OPT_type_workflow')"
run_test "type_flag_also_updates_priority" "1" "$(count_log_matches 'fieldId=PVTSSF_priority')"

echo ""
echo "=== create: Linear provider — emits TRACKER_ACTION_REQUIRED=create_item title=... ==="

# To test the Linear path, temporarily replace .ai-dev-workflow.yaml with a
# Linear-provider config. The cleanup() trap (registered at the top of this
# script) restores the original on any exit — success or failure — so a
# set -e abort between the overwrite and explicit restore cannot leave the
# repo config permanently clobbered.
# The add-backlog-item.sh script resolves the config file via workflow_config_file(),
# which always points to $(workflow_repo_root)/.ai-dev-workflow.yaml.
_config_backup="$TMP_ROOT/ai-dev-workflow.yaml.bak"

if [ ! -f "$_config_file" ]; then
  echo "SKIP: $_config_file not found; skipping Linear provider create_item tests." >&2
  echo ""
  echo "Test summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
  exit "$( [ "$FAIL_COUNT" -ne 0 ] && echo 1 || echo 0 )"
fi

cp "$_config_file" "$_config_backup"

# Write a minimal linear config for the duration of these tests.
cat > "$_config_file" <<'LINEAR_CONFIG'
schema_version: 2
issue_tracker:
  provider: linear
LINEAR_CONFIG

run_create "ok" --title "Test Linear Item" --body "body"
_linear_stdout="$(get_stdout)"
_linear_stderr="$(get_stderr)"

# Restore the real config immediately (cleanup() also does this on any exit).
cp "$_config_backup" "$_config_file"

# The create_item action emits TRACKER_ACTION_REQUIRED=create_item title='<title>'
# to stdout and exits 0. Multi-word titles are single-quoted so parsers can
# unambiguously extract the value. gh issue create must NOT be called.
run_test "linear_create_item_exits_zero" "0" "$(get_exit)"

case "$_linear_stdout" in
  *"TRACKER_ACTION_REQUIRED=create_item"*) linear_signal_result="has-signal" ;;
  *) linear_signal_result="no-signal" ;;
esac
run_test "linear_create_item_emits_tracker_action_required" "has-signal" "$linear_signal_result"

# Multi-word title "Test Linear Item" must be single-quoted in the output.
case "$_linear_stdout" in
  *"title='Test Linear Item'"*) linear_title_result="has-title" ;;
  *) linear_title_result="no-title" ;;
esac
run_test "linear_create_item_uses_title_key_not_issue_key" "has-title" "$linear_title_result"

# No gh issue create should be invoked for Linear.
run_test "linear_create_item_skips_gh_create" "0" "$(count_log_matches 'issue create')"

# Guidance message goes to stderr.
case "$_linear_stderr" in
  *"Linear backlog creation requires the orchestrator"*) linear_guidance_result="has-guidance" ;;
  *) linear_guidance_result="no-guidance" ;;
esac
run_test "linear_create_item_stderr_guidance" "has-guidance" "$linear_guidance_result"

echo ""
echo "Test summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
