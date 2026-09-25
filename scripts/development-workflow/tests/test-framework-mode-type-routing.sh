#!/usr/bin/env bash
# test-framework-mode-type-routing.sh — Unit tests for #1583's two new
# scripts: list_open_framework_items.sh (the framework-item lookup wrapper)
# and framework-mode-backlog-type-gate.sh (the Backlog routing gate).
#
# Covers:
#   - list_open_framework_items.sh: consumer delegation, framework-mode
#     ok/empty outcomes, and all nine closed-list `unavailable` causes
#     (framework-lookup-ignores-type-field also asserted).
#   - framework-mode-backlog-type-gate.sh: usage-error contract
#     (gate-usage-errors), consumer_mode passthrough, and the routing
#     decision matrix (type_routes_today, type_absent, status_unreconciled,
#     pipeline_already_chosen, stale_backlog_reconciled,
#     branch_or_pr_in_flight, branch_evidence_unavailable, and the
#     genuine stop/hold outcome).
#
# Usage: bash scripts/development-workflow/tests/test-framework-mode-type-routing.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
WRAPPER="$REPO_ROOT/scripts/development-workflow/list_open_framework_items.sh"
GATE="$REPO_ROOT/scripts/development-workflow/framework-mode-backlog-type-gate.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/calls.log"
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

REAL_CONFIG="$REPO_ROOT/.ai-dev-workflow.yaml"
REAL_CONFIG_BACKUP="$TMP_ROOT/real-config-master.bak"
cp "$REAL_CONFIG" "$REAL_CONFIG_BACKUP"

cleanup() {
  # Safety net: restore the real repo config even if a test aborts mid-swap
  # (each swap site also restores explicitly on its own success path).
  if [ -f "$REAL_CONFIG_BACKUP" ]; then
    cp "$REAL_CONFIG_BACKUP" "$REAL_CONFIG"
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

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

kv() {
  # kv <key> <output-text> — extract the value of a KEY=value line.
  printf '%s\n' "$2" | awk -F'=' -v k="$1" '$1 == k { sub(k "=", ""); print; exit }'
}

# --- Mock gh: controlled per-call-type failure via env switches ----------

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"

case "$*" in
  "repo view --json owner --jq .owner.login")
    [ "${MOCK_OWNER_MODE:-ok}" = "fail" ] && exit 42
    printf 'lhpaul\n'
    ;;
  "repo view --json name --jq .name")
    [ "${MOCK_OWNER_MODE:-ok}" = "fail" ] && exit 42
    printf 'ai-dev-framework-template\n'
    ;;
  "issue list --repo lhpaul/ai-dev-framework-template --state open --limit 1000 --json number,title,labels,createdAt,url")
    case "${MOCK_ISSUE_LIST_MODE:-ok}" in
      fail) exit 42 ;;
      blank) printf '' ;;
      malformed) printf 'not json at all' ;;
      *)
        cat <<'JSON'
[{"number":900,"title":"Feature helper issue","labels":[],"createdAt":"2026-01-01T00:00:00Z","url":"https://github.com/lhpaul/ai-dev-framework-template/issues/900"},{"number":901,"title":"Done bug helper issue","labels":[],"createdAt":"2026-01-01T00:00:00Z","url":"https://github.com/lhpaul/ai-dev-framework-template/issues/901"}]
JSON
        ;;
    esac
    ;;
  "project item-list 1 --owner lhpaul --limit 1000 --format json")
    case "${MOCK_ITEM_LIST_MODE:-ok}" in
      fail) exit 42 ;;
      unparseable) printf 'not json' ;;
      empty) printf '{"items":[]}\n' ;;
      renamed_type_field)
        cat <<'JSON'
{"items":[{"content":{"number":900},"status":"Backlog","priority":"High","title":"Feature helper issue"}]}
JSON
        ;;
      *)
        cat <<'JSON'
{"items":[{"content":{"number":900},"status":"Backlog","priority":"High","type":"Feature","title":"Feature helper issue"},{"content":{"number":901},"status":"Done","priority":"High","type":"Bug","title":"Done bug helper issue"}]}
JSON
        ;;
    esac
    ;;
  *"pr list --state open"*)
    if [ "${MOCK_PR_LIST_MODE:-empty}" = "fail" ]; then
      exit 42
    fi
    printf '[]\n'
    ;;
  *"pr list --state merged"*)
    if [ "${MOCK_PR_LIST_MODE:-empty}" = "fail" ]; then
      exit 42
    fi
    printf '[]\n'
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"

# Minimal git passthrough mock: only intercepts `git remote get-url origin`
# when MOCK_GIT_REMOTE_MODE=fail (so owner/repo-name resolution's git-remote
# fallback tier can be forced to fail alongside a failing gh mock — needed
# to distinguish project_owner_unresolvable from repo_unresolvable, since
# both read the same underlying gh/git calls). Every other invocation
# passes through to the real git binary.
REAL_GIT="$(command -v git)"
cat > "$MOCK_BIN/git" <<MOCK_GIT
#!/usr/bin/env bash
if [ "\${MOCK_GIT_REMOTE_MODE:-ok}" = "fail" ] && [ "\${1:-}" = "remote" ] && [ "\${2:-}" = "get-url" ]; then
  exit 1
fi
exec "$REAL_GIT" "\$@"
MOCK_GIT
chmod +x "$MOCK_BIN/git"

export PATH="$MOCK_BIN:$PATH"
export MOCK_GH_CALL_LOG="$CALL_LOG"
export GITHUB_PROJECT_NUMBER="1"

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"

reset_log() { : > "$CALL_LOG"; }

# ===========================================================================
# list_open_framework_items.sh
# ===========================================================================

echo ""
echo "=== list_open_framework_items.sh: consumer mode delegates, all 3 keys ==="

consumer_config="$TMP_ROOT/consumer.yaml"
cat > "$consumer_config" <<'EOF'
schema_version: 2
issue_tracker:
  provider: github_projects
  project_number: 1
EOF

run_wrapper_in_repo() {
  # run_wrapper_in_repo <config-file> — copies the wrapper's own repo tree
  # into a scratch dir with the given config swapped in, then runs it there
  # (cd_workflow_repo_root walks up from the script's own location, so the
  # wrapper must be invoked from a real checkout; the fixture config is
  # swapped via AI_DEV_WORKFLOW_CONFIG_FILE... but workflow_template_is_template
  # reads workflow_config_file() directly, so instead swap the real repo
  # config file for the duration of the call).
  local config_file="$1"
  shift
  local real_config="$REPO_ROOT/.ai-dev-workflow.yaml"
  local backup="$TMP_ROOT/real-config.bak"
  cp "$real_config" "$backup"
  cp "$config_file" "$real_config"
  set +e
  "$WRAPPER" "$@" >"$TMP_ROOT/wrapper-stdout.log" 2>"$TMP_ROOT/wrapper-stderr.log"
  local rc=$?
  set -e
  cp "$backup" "$real_config"
  return "$rc"
}

reset_log
run_wrapper_in_repo "$consumer_config"
consumer_out="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "consumer_status_ok" "ok" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$consumer_out")"
run_test "consumer_reason_empty" "" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$consumer_out")"
run_test "consumer_json_present" "yes" "$(printf '%s\n' "$consumer_out" | grep -q '^FRAMEWORK_ITEMS_JSON=' && echo yes || echo no)"
run_test "consumer_delegates_to_issue_list" "1" "$(grep -c 'issue list --repo' "$CALL_LOG")"

echo ""
echo "=== list_open_framework_items.sh: framework mode — ok / empty ==="

framework_config="$TMP_ROOT/framework.yaml"
cat > "$framework_config" <<'EOF'
schema_version: 2
issue_tracker:
  provider: github_projects
  project_number: 1
template:
  is_template: true
EOF

reset_log
run_wrapper_in_repo "$framework_config"
framework_out="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "framework_status_ok" "ok" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$framework_out")"
run_test "framework_reason_empty" "" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$framework_out")"
# Mixed types (Feature open, Bug terminal/Done filtered) — one non-terminal
# result: the open Feature-typed item, proving Type is not filtered.
run_test "framework_json_has_nonterminal_item" "1" "$(printf '%s\n' "$framework_out" | grep 'FRAMEWORK_ITEMS_JSON=' | grep -o '"number":900' | wc -l | tr -d ' ')"
run_test "framework_json_excludes_terminal_item" "0" "$(printf '%s\n' "$framework_out" | grep 'FRAMEWORK_ITEMS_JSON=' | grep -o '"number":901' | wc -l | tr -d ' ')"

reset_log
MOCK_ITEM_LIST_MODE=empty run_wrapper_in_repo "$framework_config"
framework_empty_out="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "framework_empty_status" "empty" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$framework_empty_out")"
run_test "framework_empty_reason_empty" "" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$framework_empty_out")"
run_test "framework_empty_json_empty_array" "FRAMEWORK_ITEMS_JSON=[]" "$(printf '%s\n' "$framework_empty_out" | grep '^FRAMEWORK_ITEMS_JSON=')"

echo ""
echo "=== list_open_framework_items.sh: framework-lookup-ignores-type-field ==="

reset_log
MOCK_ITEM_LIST_MODE=renamed_type_field run_wrapper_in_repo "$framework_config"
renamed_out="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "framework_lookup_ignores_type_field_status_ok" "ok" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$renamed_out")"

echo ""
echo "=== list_open_framework_items.sh: nine closed-list unavailable causes ==="

no_provider_config="$TMP_ROOT/no-provider.yaml"
cat > "$no_provider_config" <<'EOF'
schema_version: 2
issue_tracker:
  provider: linear
template:
  is_template: true
EOF
reset_log
run_wrapper_in_repo "$no_provider_config"
out1="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "lookup-unavailable-provider-unsupported_status" "unavailable" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$out1")"
run_test "lookup-unavailable-provider-unsupported_reason" "provider_unsupported" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$out1")"
run_test "lookup-unavailable-provider-unsupported_json" "FRAMEWORK_ITEMS_JSON=[]" "$(printf '%s\n' "$out1" | grep '^FRAMEWORK_ITEMS_JSON=')"

no_project_number_config="$TMP_ROOT/no-project-number.yaml"
cat > "$no_project_number_config" <<'EOF'
schema_version: 2
issue_tracker:
  provider: github_projects
template:
  is_template: true
EOF
reset_log
GITHUB_PROJECT_NUMBER="" run_wrapper_in_repo "$no_project_number_config"
out2="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "lookup-unavailable-project-number-missing_status" "unavailable" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$out2")"
run_test "lookup-unavailable-project-number-missing_reason" "project_number_missing" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$out2")"

reset_log
GITHUB_PROJECT_NUMBER="abc" run_wrapper_in_repo "$framework_config"
out3="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "lookup-unavailable-project-number-invalid_status" "unavailable" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$out3")"
run_test "lookup-unavailable-project-number-invalid_reason" "project_number_invalid" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$out3")"

# project_owner_unresolvable: no GITHUB_PROJECT_OWNER env override, gh repo
# view fails, AND the git-remote fallback tier also fails (this worktree has
# a real origin remote, so both failure sources must be forced together).
reset_log
MOCK_OWNER_MODE=fail MOCK_GIT_REMOTE_MODE=fail run_wrapper_in_repo "$framework_config"
out4="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "lookup-unavailable-project-owner-unresolvable_status" "unavailable" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$out4")"
run_test "lookup-unavailable-project-owner-unresolvable_reason" "project_owner_unresolvable" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$out4")"

# repo_unresolvable: project owner resolves via an explicit GITHUB_PROJECT_OWNER
# env override (tier 1 — no gh/git call at all), but repo owner/name
# resolution — a separate helper that never consults that env var — still
# fails on both its gh and git-remote tiers.
reset_log
GITHUB_PROJECT_OWNER="lhpaul" MOCK_OWNER_MODE=fail MOCK_GIT_REMOTE_MODE=fail run_wrapper_in_repo "$framework_config"
out5="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "lookup-unavailable-repo-unresolvable_status" "unavailable" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$out5")"
run_test "lookup-unavailable-repo-unresolvable_reason" "repo_unresolvable" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$out5")"

reset_log
MOCK_ISSUE_LIST_MODE=fail run_wrapper_in_repo "$framework_config"
out6="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "lookup-unavailable-issue-list-failed_status" "unavailable" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$out6")"
run_test "lookup-unavailable-issue-list-failed_reason" "issue_list_failed" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$out6")"

reset_log
MOCK_ISSUE_LIST_MODE=blank run_wrapper_in_repo "$framework_config"
out7="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "lookup-unavailable-issue-list-blank-or-malformed_blank_status" "unavailable" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$out7")"
run_test "lookup-unavailable-issue-list-blank-or-malformed_blank_reason" "issue_list_blank_or_malformed" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$out7")"
run_test "lookup-unavailable-issue-list-blank-or-malformed_blank_not_empty" "not-empty" "$([ "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$out7")" = "empty" ] && echo empty || echo not-empty)"

reset_log
MOCK_ISSUE_LIST_MODE=malformed run_wrapper_in_repo "$framework_config"
out8="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "lookup-unavailable-issue-list-blank-or-malformed_malformed_status" "unavailable" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$out8")"
run_test "lookup-unavailable-issue-list-blank-or-malformed_malformed_reason" "issue_list_blank_or_malformed" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$out8")"
run_test "lookup-unavailable-issue-list-blank-or-malformed_malformed_not_item_list_unparseable" "not-item-list-unparseable" "$([ "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$out8")" = "item_list_unparseable" ] && echo item_list_unparseable || echo not-item-list-unparseable)"

reset_log
MOCK_ITEM_LIST_MODE=fail run_wrapper_in_repo "$framework_config"
out9="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "lookup-unavailable-item-list-failed_status" "unavailable" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$out9")"
run_test "lookup-unavailable-item-list-failed_reason" "item_list_failed" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$out9")"

reset_log
MOCK_ITEM_LIST_MODE=unparseable run_wrapper_in_repo "$framework_config"
out10="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "lookup-unavailable-item-list-unparseable_status" "unavailable" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$out10")"
run_test "lookup-unavailable-item-list-unparseable_reason" "item_list_unparseable" "$(kv FRAMEWORK_ITEMS_LOOKUP_REASON "$out10")"

# ===========================================================================
# framework-mode-backlog-type-gate.sh
# ===========================================================================

echo ""
echo "=== framework-mode-backlog-type-gate.sh: gate-usage-errors ==="

gate_usage_case() {
  local name="$1"; shift
  local out err rc
  set +e
  out="$("$GATE" "$@" 2>"$TMP_ROOT/gate-stderr.log")"
  rc=$?
  set -e
  err="$(cat "$TMP_ROOT/gate-stderr.log")"
  run_test "${name}_exit64" "64" "$rc"
  run_test "${name}_no_result_line" "no" "$(printf '%s\n' "$out" | grep -q '^RESULT=' && echo yes || echo no)"
  run_test "${name}_stderr_nonempty" "yes" "$([ -n "$err" ] && echo yes || echo no)"
}

gate_usage_case "gate_usage_errors_missing_issue" --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single
gate_usage_case "gate_usage_errors_missing_status" --issue 1 --artifact-stage '' --branch-pr-evidence none --caller single
gate_usage_case "gate_usage_errors_missing_artifact_stage" --issue 1 --status Backlog --branch-pr-evidence none --caller single
gate_usage_case "gate_usage_errors_missing_caller" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence none
gate_usage_case "gate_usage_errors_bad_caller" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller bogus
gate_usage_case "gate_usage_errors_bad_artifact_stage" --issue 1 --status Backlog --artifact-stage Frobnicated --branch-pr-evidence none --caller single
gate_usage_case "gate_usage_errors_missing_branch_pr_evidence" --issue 1 --status Backlog --artifact-stage '' --caller single
gate_usage_case "gate_usage_errors_bad_branch_pr_evidence" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence maybe --caller single
gate_usage_case "gate_usage_errors_nonnumeric_issue" --issue abc --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single
gate_usage_case "gate_usage_errors_flag_no_value" --issue
gate_usage_case "gate_usage_errors_unknown_flag" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single --bogus-flag value

echo ""
echo "=== framework-mode-backlog-type-gate.sh: empty status/artifact-stage are accepted values ==="

empty_values_out="$("$GATE" --issue 1 --status '' --artifact-stage '' --branch-pr-evidence none --caller single --type Feature)"
run_test "gate_empty_status_and_artifact_stage_accepted_exit0" "0" "$?"
run_test "gate_empty_status_and_artifact_stage_result_present" "yes" "$(printf '%s\n' "$empty_values_out" | grep -q '^RESULT=' && echo yes || echo no)"

echo ""
echo "=== framework-mode-backlog-type-gate.sh: routing decision matrix ==="

gate_case() {
  local name="$1" expected_result="$2" expected_reason="$3"; shift 3
  local out
  out="$("$GATE" "$@")"
  run_test "${name}_result" "$expected_result" "$(kv RESULT "$out")"
  run_test "${name}_reason" "$expected_reason" "$(kv REASON "$out")"
}

_consumer_backup="$TMP_ROOT/consumer-swap.bak"
cp "$REPO_ROOT/.ai-dev-workflow.yaml" "$_consumer_backup"
cp "$consumer_config" "$REPO_ROOT/.ai-dev-workflow.yaml"
consumer_gate_out="$("$GATE" --repo-root "$REPO_ROOT" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single --type Workflow)"
cp "$_consumer_backup" "$REPO_ROOT/.ai-dev-workflow.yaml"
run_test "consumer_mode_workflow_passes" "pass" "$(kv RESULT "$consumer_gate_out")"
run_test "consumer_mode_workflow_reason" "consumer_mode" "$(kv REASON "$consumer_gate_out")"

gate_case "type_routes_today_feature" pass type_routes_today \
  --repo-root "$REPO_ROOT" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single --type Feature

gate_case "type_absent" pass type_absent \
  --repo-root "$REPO_ROOT" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single --type ""

gate_case "status_unreconciled" pass status_unreconciled \
  --repo-root "$REPO_ROOT" --issue 1 --status "Some Unknown Status" --artifact-stage '' --branch-pr-evidence none --caller single --type Workflow

gate_case "pipeline_already_chosen_in_development" pass pipeline_already_chosen \
  --repo-root "$REPO_ROOT" --issue 1 --status "In Development" --artifact-stage '' --branch-pr-evidence none --caller single --type Workflow

for _status in "Writing Spec" "Spec in Review" "Spec Ready" "Writing Plan" "Plan in Review" "Plan Ready" "In Development" "Development in Review" "Merged" "Released"; do
  _out="$("$GATE" --repo-root "$REPO_ROOT" --issue 1 --status "$_status" --artifact-stage '' --branch-pr-evidence none --caller single --type Workflow)"
  run_test "framework_post_backlog_statuses_pass_${_status// /_}" "pass" "$(kv RESULT "$_out")"
  run_test "framework_post_backlog_statuses_pass_${_status// /_}_reason" "pipeline_already_chosen" "$(kv REASON "$_out")"
done

gate_case "stale_backlog_reconciled_spec_ready" pass stale_backlog_reconciled \
  --repo-root "$REPO_ROOT" --issue 1 --status Backlog --artifact-stage "Spec Ready" --branch-pr-evidence none --caller single --type Workflow

gate_case "stale_backlog_reconciled_in_development" pass stale_backlog_reconciled \
  --repo-root "$REPO_ROOT" --issue 1 --status Backlog --artifact-stage "In Development" --branch-pr-evidence none --caller single --type Workflow

gate_case "stale_backlog_active_fix_branch_continues" pass branch_or_pr_in_flight \
  --repo-root "$REPO_ROOT" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence present --caller single --type Workflow

gate_case "branch_evidence_unavailable_defers" pass branch_evidence_unavailable \
  --repo-root "$REPO_ROOT" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence unavailable --caller single --type Workflow
_branch_evidence_unavailable_out="$("$GATE" --repo-root "$REPO_ROOT" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence unavailable --caller single --type Workflow)"
run_test "branch_evidence_unavailable_defers_check_deferred" "deferred" "$(kv MISCLASSIFIED_TYPE_CHECK "$_branch_evidence_unavailable_out")"

echo ""
echo "=== framework-mode-backlog-type-gate.sh: single-item stop / scan hold (the case the feature exists for) ==="

backlog_no_folder_no_branch_stop_out="$("$GATE" --repo-root "$REPO_ROOT" --issue 1583 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single --type Workflow)"
run_test "backlog_no_folder_no_branch_stops_result" "stop" "$(kv RESULT "$backlog_no_folder_no_branch_stop_out")"
run_test "backlog_no_folder_no_branch_stops_condition" "missing_tracker_context" "$(kv STOP_CONDITION "$backlog_no_folder_no_branch_stop_out")"
run_test "backlog_no_folder_no_branch_stops_item" "#1583" "$(kv ITEM "$backlog_no_folder_no_branch_stop_out")"
case "$(kv REASON_TEXT "$backlog_no_folder_no_branch_stop_out")" in
  *"#1583"*) run_test "backlog_no_folder_no_branch_stops_names_item" "yes" "yes" ;;
  *) run_test "backlog_no_folder_no_branch_stops_names_item" "yes" "no" ;;
esac

backlog_no_folder_no_branch_hold_out="$("$GATE" --repo-root "$REPO_ROOT" --issue 1583 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller scan --type Workflow)"
run_test "scan_backlog_no_artifacts_held_result" "hold" "$(kv RESULT "$backlog_no_folder_no_branch_hold_out")"
run_test "scan_backlog_no_artifacts_held_no_stop_condition" "no" "$(printf '%s\n' "$backlog_no_folder_no_branch_hold_out" | grep -q '^STOP_CONDITION=' && echo yes || echo no)"
run_test "scan_backlog_no_artifacts_held_item" "#1583" "$(kv ITEM "$backlog_no_folder_no_branch_hold_out")"

echo ""
echo "=== framework-mode-backlog-type-gate.sh: stop-path-no-mutation ==="
reset_log
"$GATE" --repo-root "$REPO_ROOT" --issue 1583 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single --type Workflow >/dev/null
run_test "stop_path_no_mutation_no_gh_calls" "0" "$(wc -l < "$CALL_LOG" | tr -d ' ')"

echo ""
echo "Test summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
