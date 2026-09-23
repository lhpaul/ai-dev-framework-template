#!/usr/bin/env bash
# test-add-backlog-item.sh — Unit tests for add-backlog-item.sh create flow.
#
# Exercises issue #965's Priority/Size field updates, issue #1501's fix for
# the inverted Medium/Normal priority alias (the board has no "Normal"
# option; "Medium" is the real board value), and issue #1778's fail-open
# fix (Status/Type/Size writes could silently not land — the mock `gh`
# below is stateful specifically so it can reproduce that: it tracks
# whether the item has actually been added to the board yet, and what each
# field's value actually is after each mutation, instead of always
# returning a static "everything already matches" response):
#   1. Malformed gh output warns and skips project field updates
#   2. Non-numeric issue number in URL warns and skips project field updates
#   3. Happy path: URL parsed, board membership checked, Priority defaults to
#      Medium, and every field (including Status) is verified against the
#      board's actual state before exiting
#   4. --priority flag: uses supplied value instead of the Medium default
#   5. --size flag: triggers Size field update
#   6. No --size: Size field update is not called
#   7. --type flag: triggers Type field update
#   8. A priority value that does not resolve against the board's actual
#      Priority options (issue #1501) is a hard error: create exits non-zero
#      and no mutation is sent.
#   9. issue #1778 regressions: a field write whose GraphQL mutation reports
#      success but silently does not land (the exact "200 OK, value never
#      stuck" symptom from the issue) is caught by post-creation
#      verification and turned into a loud, non-zero failure — for Type,
#      Size, and Status independently.
#  10. issue #1778: GitHub Projects' read-after-write lag on a just-added
#      item — a lookup immediately after `gh project item-add` finding
#      nothing — is absorbed by a bounded retry when it clears in time, and
#      surfaces as a loud failure when it does not.
#  11. issue #1778: the hardcoded 'Type' wording in the "has no Type value"
#      warning honours issue_tracker.custom_fields.type_field.
#
# Usage: bash scripts/development-workflow/tests/test-add-backlog-item.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
SCRIPT="$REPO_ROOT/scripts/development-workflow/add-backlog-item.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/calls.log"
STATE_FILE="$TMP_ROOT/state.env"
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

# _config_backup is set before the linear/custom-type-field test sections
# overwrite .ai-dev-workflow.yaml; cleanup restores it on any exit
# (including set -e).
_config_backup=""
_config_file="$REPO_ROOT/.ai-dev-workflow.yaml"

cleanup() {
  # Restore .ai-dev-workflow.yaml if it was swapped out by a test section.
  # The guard ([ -f "$_config_backup" ]) ensures cp is only called when the
  # backup was successfully created; do not suppress errors — a restore failure
  # means the workspace is clobbered and the test runner must know.
  if [ -n "$_config_backup" ] && [ -f "$_config_backup" ]; then
    cp "$_config_backup" "$_config_file"
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

# The mock `gh` tracks project-item state in $STATE_FILE (a flat, sourced
# key=value file — bash 3.2 compatible, no associative arrays) so that:
#   - the board-membership check before item-add correctly reports "not on
#     board" for a freshly created issue (the old static mock always
#     reported the item as already present, which never exercised the real
#     add-then-set-initial-status path);
#   - each field mutation actually updates the value a later read-back sees,
#     instead of every read always echoing the same canned "Feature" type
#     and no status;
#   - MOCK_*_UPDATE_MODE=silent_drop can reproduce issue #1778's core
#     symptom — a mutation that returns a valid success payload but never
#     changes the field the caller asked for;
#   - MOCK_LOOKUP_MISSING_UNTIL can reproduce GitHub Projects' read-after-
#     write lag on a just-added item (a lookup that finds nothing for the
#     first N calls after the item was added).
cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"

STATE_FILE="${MOCK_GH_STATE_FILE:?MOCK_GH_STATE_FILE must be set}"
ON_BOARD="no"
ITEM_STATUS=""
ITEM_TYPE=""
ITEM_PRIORITY=""
ITEM_SIZE=""
LOOKUP_COUNT="0"
# shellcheck disable=SC1090 # generated, test-local state file
[ -f "$STATE_FILE" ] && . "$STATE_FILE"

save_state() {
  cat > "$STATE_FILE" <<STATE
ON_BOARD="$ON_BOARD"
ITEM_STATUS="$ITEM_STATUS"
ITEM_TYPE="$ITEM_TYPE"
ITEM_PRIORITY="$ITEM_PRIORITY"
ITEM_SIZE="$ITEM_SIZE"
LOOKUP_COUNT="$LOOKUP_COUNT"
STATE
}

# Maps the option IDs this mock's "fields(first:" response hands out back to
# their display names, so the mutation handler below can tell which value a
# given optionId= actually represents without a second round trip.
option_id_to_name() {
  case "$1" in
    OPT_urgent) printf 'Urgent' ;;
    OPT_high) printf 'High' ;;
    OPT_medium) printf 'Medium' ;;
    OPT_normal) printf 'Normal' ;;
    OPT_low) printf 'Low' ;;
    OPT_p0) printf 'P0' ;;
    OPT_p1) printf 'P1' ;;
    OPT_size_xs) printf 'XS' ;;
    OPT_size_s) printf 'S' ;;
    OPT_size_m) printf 'M' ;;
    OPT_size_l) printf 'L' ;;
    OPT_size_xl) printf 'XL' ;;
    OPT_type_feature) printf 'Feature' ;;
    OPT_type_bug) printf 'Bug' ;;
    OPT_type_refactor) printf 'Refactor' ;;
    OPT_type_workflow) printf 'Workflow' ;;
    OPT_status_backlog) printf 'Backlog' ;;
    OPT_status_in_dev) printf 'In Development' ;;
    OPT_status_merged) printf 'Merged' ;;
    *) printf '' ;;
  esac
}

extract_arg_value() {
  # Extracts the value of a "-f name=value"-shaped token from "$@" (as
  # passed through as positional params by the caller below).
  local prefix="$1"
  shift
  local tok
  for tok in "$@"; do
    case "$tok" in
      "$prefix"*) printf '%s' "${tok#"$prefix"}"; return 0 ;;
    esac
  done
  printf ''
}

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
    if [ "${MOCK_ITEM_ADD_MODE:-ok}" = "fail" ]; then
      printf 'item-add failed\n' >&2
      exit 1
    fi
    ON_BOARD="yes"
    save_state
    printf 'PVTI_added\n'
    ;;
  *"api graphql"*)
    case "$*" in
      *"projectV2(number:"*)
        printf '{"data":{"user":{"projectV2":{"id":"PVT_project_1"}},"organization":null}}\n'
        ;;
      *"projectItems(first:"*)
        LOOKUP_COUNT=$((LOOKUP_COUNT + 1))
        save_state
        if [ "$ON_BOARD" != "yes" ]; then
          printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}\n'
        elif [ -n "${MOCK_LOOKUP_MISSING_UNTIL:-}" ] && [ "$LOOKUP_COUNT" -le "$MOCK_LOOKUP_MISSING_UNTIL" ]; then
          # Simulates GitHub Projects' read-after-write lag: the item was
          # just added, but a lookup issued moments later still finds
          # nothing for the configured number of calls (issue #1778).
          printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}\n'
        else
          printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_item_123","project":{"id":"PVT_project_1","number":1},"status":{"name":"%s"},"configuredType":{"name":"%s"},"customType":null,"compactCustomType":null,"type":{"name":"%s"},"priority":{"name":"%s"},"size":{"name":"%s"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}\n' \
            "$ITEM_STATUS" "$ITEM_TYPE" "$ITEM_TYPE" "$ITEM_PRIORITY" "$ITEM_SIZE"
        fi
        ;;
      *"fields(first:"*)
        case "${MOCK_PRIORITY_FIELD_MODE:-medium}" in
          normal_only)
            # Simulates a downstream board still configured per the
            # framework's pre-#1501 docs: Urgent, High, Normal, Low — no
            # "Medium" option (issue #1501 code review, "Preserve
            # compatibility with Normal-priority boards").
            printf '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status","options":[{"id":"OPT_status_backlog","name":"Backlog"},{"id":"OPT_status_in_dev","name":"In Development"},{"id":"OPT_status_merged","name":"Merged"}]},{"id":"PVTSSF_priority","name":"Priority","options":[{"id":"OPT_urgent","name":"Urgent"},{"id":"OPT_high","name":"High"},{"id":"OPT_normal","name":"Normal"},{"id":"OPT_low","name":"Low"}]},{"id":"PVTSSF_size","name":"Size","options":[{"id":"OPT_size_xs","name":"XS"},{"id":"OPT_size_s","name":"S"},{"id":"OPT_size_m","name":"M"},{"id":"OPT_size_l","name":"L"},{"id":"OPT_size_xl","name":"XL"}]},{"id":"PVTSSF_type","name":"Type","options":[{"id":"OPT_type_feature","name":"Feature"},{"id":"OPT_type_bug","name":"Bug"},{"id":"OPT_type_refactor","name":"Refactor"},{"id":"OPT_type_workflow","name":"Workflow"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}\n'
            ;;
          neither)
            # Simulates a board using an entirely different Priority
            # vocabulary (neither "Medium" nor "Normal" present).
            printf '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status","options":[{"id":"OPT_status_backlog","name":"Backlog"},{"id":"OPT_status_in_dev","name":"In Development"},{"id":"OPT_status_merged","name":"Merged"}]},{"id":"PVTSSF_priority","name":"Priority","options":[{"id":"OPT_p0","name":"P0"},{"id":"OPT_p1","name":"P1"}]},{"id":"PVTSSF_size","name":"Size","options":[{"id":"OPT_size_xs","name":"XS"},{"id":"OPT_size_s","name":"S"},{"id":"OPT_size_m","name":"M"},{"id":"OPT_size_l","name":"L"},{"id":"OPT_size_xl","name":"XL"}]},{"id":"PVTSSF_type","name":"Type","options":[{"id":"OPT_type_feature","name":"Feature"},{"id":"OPT_type_bug","name":"Bug"},{"id":"OPT_type_refactor","name":"Refactor"},{"id":"OPT_type_workflow","name":"Workflow"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}\n'
            ;;
          custom_type_field)
            # Simulates a board whose classification field is named "Work
            # type" (issue_tracker.custom_fields.type_field: "Work type"),
            # with no field literally named "Type" (issue #1778, criterion 4).
            printf '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status","options":[{"id":"OPT_status_backlog","name":"Backlog"},{"id":"OPT_status_in_dev","name":"In Development"},{"id":"OPT_status_merged","name":"Merged"}]},{"id":"PVTSSF_priority","name":"Priority","options":[{"id":"OPT_urgent","name":"Urgent"},{"id":"OPT_high","name":"High"},{"id":"OPT_medium","name":"Medium"},{"id":"OPT_low","name":"Low"}]},{"id":"PVTSSF_size","name":"Size","options":[{"id":"OPT_size_xs","name":"XS"},{"id":"OPT_size_s","name":"S"},{"id":"OPT_size_m","name":"M"},{"id":"OPT_size_l","name":"L"},{"id":"OPT_size_xl","name":"XL"}]},{"id":"PVTSSF_worktype","name":"Work type","options":[{"id":"OPT_type_feature","name":"Feature"},{"id":"OPT_type_bug","name":"Bug"},{"id":"OPT_type_refactor","name":"Refactor"},{"id":"OPT_type_workflow","name":"Workflow"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}\n'
            ;;
          *)
            # Matches the real board's Priority options verified on issue
            # #1501: Urgent, High, Medium, Low — there is no "Normal" option.
            printf '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status","options":[{"id":"OPT_status_backlog","name":"Backlog"},{"id":"OPT_status_in_dev","name":"In Development"},{"id":"OPT_status_merged","name":"Merged"}]},{"id":"PVTSSF_priority","name":"Priority","options":[{"id":"OPT_urgent","name":"Urgent"},{"id":"OPT_high","name":"High"},{"id":"OPT_medium","name":"Medium"},{"id":"OPT_low","name":"Low"}]},{"id":"PVTSSF_size","name":"Size","options":[{"id":"OPT_size_xs","name":"XS"},{"id":"OPT_size_s","name":"S"},{"id":"OPT_size_m","name":"M"},{"id":"OPT_size_l","name":"L"},{"id":"OPT_size_xl","name":"XL"}]},{"id":"PVTSSF_type","name":"Type","options":[{"id":"OPT_type_feature","name":"Feature"},{"id":"OPT_type_bug","name":"Bug"},{"id":"OPT_type_refactor","name":"Refactor"},{"id":"OPT_type_workflow","name":"Workflow"}]}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}\n'
            ;;
        esac
        ;;
      *"updateProjectV2ItemFieldValue"*)
        field_id="$(extract_arg_value "fieldId=" "$@")"
        option_id="$(extract_arg_value "optionId=" "$@")"
        option_name="$(option_id_to_name "$option_id")"
        case "$field_id" in
          PVTSSF_status)
            mode="${MOCK_STATUS_UPDATE_MODE:-ok}"
            ;;
          PVTSSF_type|PVTSSF_worktype)
            mode="${MOCK_TYPE_UPDATE_MODE:-ok}"
            ;;
          PVTSSF_priority)
            mode="${MOCK_PRIORITY_UPDATE_MODE:-ok}"
            ;;
          PVTSSF_size)
            mode="${MOCK_SIZE_UPDATE_MODE:-ok}"
            ;;
          *)
            mode="ok"
            ;;
        esac
        if [ "$mode" = "fail" ]; then
          printf 'transient GraphQL write failure\n' >&2
          exit 42
        fi
        if [ "$mode" != "silent_drop" ]; then
          # A real write: update the tracked state so a later read-back sees
          # it. "silent_drop" intentionally skips this — the mutation below
          # still returns a valid success payload, reproducing issue
          # #1778's "a 200 from updateProjectV2ItemFieldValue is not
          # evidence the value stuck" symptom.
          case "$field_id" in
            PVTSSF_status) ITEM_STATUS="$option_name" ;;
            PVTSSF_type|PVTSSF_worktype) ITEM_TYPE="$option_name" ;;
            PVTSSF_priority) ITEM_PRIORITY="$option_name" ;;
            PVTSSF_size) ITEM_SIZE="$option_name" ;;
          esac
          save_state
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
export MOCK_GH_STATE_FILE="$STATE_FILE"
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
reset_state() { rm -f "$STATE_FILE"; }

count_log_matches() {
  local pattern="$1"
  awk -v p="$pattern" '$0 ~ p { c++ } END { print c+0 }' "$CALL_LOG"
}

run_create() {
  local mode="${1:-ok}"; shift
  reset_log
  reset_state
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
echo "=== create: happy path — issue URL in output, Priority defaults to Medium, all fields verified ==="

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
run_test "happy_path_adds_item_to_board" "1" "$(count_log_matches 'project item-add ')"
run_test "happy_path_sets_status_backlog" "1" "$(count_log_matches 'optionId=OPT_status_backlog')"
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
echo "=== create: Priority failure does not skip independent Type/Size updates (issue #1501 code review) ==="

export MOCK_PRIORITY_UPDATE_MODE=fail
run_create "ok" --title "Test" --body "body" --size "M" --type "Bug"
unset MOCK_PRIORITY_UPDATE_MODE
run_test "partial_success_still_exits_five_with_other_fields" "5" "$(get_exit)"
# Type and Size are independent field writes and must still be attempted
# even though Priority failed — a caller following the "retry only
# Priority" guidance must not find Type/Size permanently unset because this
# script gave up early.
run_test "partial_success_still_updates_size" "1" "$(count_log_matches 'fieldId=PVTSSF_size')"
run_test "partial_success_still_updates_type" "1" "$(count_log_matches 'fieldId=PVTSSF_type')"

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
echo "=== create (issue #1778): a Type write that reports success but silently does not land is a loud failure ==="

export MOCK_TYPE_UPDATE_MODE=silent_drop
run_create "ok" --title "Test" --body "body" --type "Bug"
unset MOCK_TYPE_UPDATE_MODE
run_test "silent_type_drop_exits_five" "5" "$(get_exit)"
silent_type_stderr="$(get_stderr)"
case "$silent_type_stderr" in
  *"Type: requested 'Bug'"*) silent_type_result="reported" ;;
  *) silent_type_result="$silent_type_stderr" ;;
esac
run_test "silent_type_drop_reports_mismatch" "reported" "$silent_type_result"
# The mutation itself must have actually been attempted (this is not the
# pre-flight validation path) — it just didn't take effect on the board.
run_test "silent_type_drop_attempted_mutation" "1" "$(count_log_matches 'fieldId=PVTSSF_type')"

echo ""
echo "=== create (issue #1778): a Size write that reports success but silently does not land is a loud failure ==="

export MOCK_SIZE_UPDATE_MODE=silent_drop
run_create "ok" --title "Test" --body "body" --size "L"
unset MOCK_SIZE_UPDATE_MODE
run_test "silent_size_drop_exits_five" "5" "$(get_exit)"
silent_size_stderr="$(get_stderr)"
case "$silent_size_stderr" in
  *"Size: requested 'L'"*) silent_size_result="reported" ;;
  *) silent_size_result="$silent_size_stderr" ;;
esac
run_test "silent_size_drop_reports_mismatch" "reported" "$silent_size_result"

echo ""
echo "=== create (issue #1778): a Status write that reports success but silently does not land is a loud failure ==="
echo "    (ensure_on_project_board itself stays fail-open by design — the create_cmd"
echo "     verification pass is what must catch this)"

export MOCK_STATUS_UPDATE_MODE=silent_drop
run_create "ok" --title "Test" --body "body"
unset MOCK_STATUS_UPDATE_MODE
run_test "silent_status_drop_exits_five" "5" "$(get_exit)"
silent_status_stderr="$(get_stderr)"
case "$silent_status_stderr" in
  *"Status: requested 'Backlog'"*) silent_status_result="reported" ;;
  *) silent_status_result="$silent_status_stderr" ;;
esac
run_test "silent_status_drop_reports_mismatch" "reported" "$silent_status_result"

echo ""
echo "=== create (issue #1778): read-after-write lag that clears within the retry budget still succeeds ==="

export MOCK_LOOKUP_MISSING_UNTIL=1
run_create "ok" --title "Test" --body "body" --type "Feature" --size "S"
unset MOCK_LOOKUP_MISSING_UNTIL
run_test "transient_lookup_lag_still_exits_zero" "0" "$(get_exit)"

echo ""
echo "=== create (issue #1778): read-after-write lag that persists past the retry budget is a loud failure ==="
echo "    (this reproduces the 'completely empty' board items reported in issue #1778 —"
echo "     Status/Type/Priority/Size all fail to resolve the item, but silently, unless caught)"

export MOCK_LOOKUP_MISSING_UNTIL=999
run_create "ok" --title "Test" --body "body" --type "Feature" --size "S"
unset MOCK_LOOKUP_MISSING_UNTIL
run_test "persistent_lookup_lag_exits_five" "5" "$(get_exit)"
persistent_lag_stderr="$(get_stderr)"
case "$persistent_lag_stderr" in
  *"item not found on the project board"*) persistent_lag_result="reported" ;;
  *) persistent_lag_result="$persistent_lag_stderr" ;;
esac
run_test "persistent_lookup_lag_reports_item_not_found" "reported" "$persistent_lag_result"

echo ""
echo "=== create (issue #1778): the 'has no Type value' warning honours custom_fields.type_field ==="

_config_backup="$TMP_ROOT/ai-dev-workflow.yaml.bak"
if [ ! -f "$_config_file" ]; then
  echo "SKIP: $_config_file not found; skipping custom type_field warning test." >&2
else
  cp "$_config_file" "$_config_backup"
  cat > "$_config_file" <<'CUSTOM_TYPE_FIELD_CONFIG'
schema_version: 2
issue_tracker:
  provider: github_projects
  project_number: 1
  custom_fields:
    type_field: Work type
CUSTOM_TYPE_FIELD_CONFIG

  # MOCK_PRIORITY_FIELD_MODE selects the whole "fields(first:" response (all
  # of Status/Priority/Size/Type-or-configured-field), not only Priority —
  # the name predates this test's Type/Size coverage. "custom_type_field"
  # selects the variant whose classification field is named "Work type".
  export MOCK_PRIORITY_FIELD_MODE=custom_type_field
  # No --type flag: the item is left with no value on "Work type", which
  # triggers the "has no Type value" warning path inside
  # workflow_github_project_item_for_issue.
  run_create "ok" --title "Test" --body "body"
  unset MOCK_PRIORITY_FIELD_MODE

  cp "$_config_backup" "$_config_file"

  custom_type_field_stderr="$(get_stderr)"
  case "$custom_type_field_stderr" in
    *"single-select field named exactly 'Work type'"*) custom_type_field_result="honours_custom_name" ;;
    *"single-select field named exactly 'Type'."*) custom_type_field_result="still_hardcoded_Type" ;;
    *) custom_type_field_result="$custom_type_field_stderr" ;;
  esac
  run_test "type_warning_honours_custom_field_name" "honours_custom_name" "$custom_type_field_result"
fi

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
