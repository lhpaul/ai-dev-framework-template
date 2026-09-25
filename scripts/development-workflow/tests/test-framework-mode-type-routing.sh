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

REAL_AGENTS="$REPO_ROOT/AGENTS.md"
REAL_AGENTS_BACKUP="$TMP_ROOT/real-agents-master.bak"
cp "$REAL_AGENTS" "$REAL_AGENTS_BACKUP"

cleanup() {
  # Safety net: restore real repo files even if a test aborts mid-swap
  # (each swap site also restores explicitly on its own success path).
  if [ -f "$REAL_CONFIG_BACKUP" ]; then
    cp "$REAL_CONFIG_BACKUP" "$REAL_CONFIG"
  fi
  if [ -f "$REAL_AGENTS_BACKUP" ]; then
    cp "$REAL_AGENTS_BACKUP" "$REAL_AGENTS"
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
      cross_repo_collision)
        # A different repository's issue #900, sharing this repo's project
        # board, must not be joined to this repo's open issue #900
        # (codex-github finding, #1583: issue numbers are not globally
        # unique across repositories in one org-owned project).
        cat <<'JSON'
{"items":[{"content":{"number":900,"repository":"https://github.com/lhpaul/some-other-repo"},"status":"Backlog","priority":"High","type":"Feature","title":"Foreign repo's issue 900"}]}
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
echo "=== list_open_framework_items.sh: cross-repo issue-number collision is excluded (codex-github finding, #1583) ==="

reset_log
MOCK_ITEM_LIST_MODE=cross_repo_collision run_wrapper_in_repo "$framework_config"
cross_repo_out="$(cat "$TMP_ROOT/wrapper-stdout.log")"
run_test "cross_repo_collision_excluded_status" "empty" "$(kv FRAMEWORK_ITEMS_LOOKUP_STATUS "$cross_repo_out")"
run_test "cross_repo_collision_excluded_json_empty" "FRAMEWORK_ITEMS_JSON=[]" "$(printf '%s\n' "$cross_repo_out" | grep '^FRAMEWORK_ITEMS_JSON=')"

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
# codex-github finding, #1583: --issue 0 (and leading-zero forms) must be
# rejected, matching run-item-scope-resolver.sh's is_positive_int (0* is
# rejected there too), not silently accepted as a routing outcome for a
# nonexistent issue #0.
gate_usage_case "gate_usage_errors_zero_issue" --issue 0 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single
gate_usage_case "gate_usage_errors_leading_zero_issue" --issue 01 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single
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

# consumer-routing-all-classes-unchanged: under consumer config, every class
# (including Workflow and no --type at all) passes as consumer_mode — the
# gate exits before reading Type at all in that mode, so re-classification
# never changes this half of the claim.
for _consumer_class in Feature Bug Refactor Workflow ""; do
  _consumer_backup3="$TMP_ROOT/consumer-swap3.bak"
  cp "$REPO_ROOT/.ai-dev-workflow.yaml" "$_consumer_backup3"
  cp "$consumer_config" "$REPO_ROOT/.ai-dev-workflow.yaml"
  _consumer_class_out="$("$GATE" --repo-root "$REPO_ROOT" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single --type "$_consumer_class")"
  cp "$_consumer_backup3" "$REPO_ROOT/.ai-dev-workflow.yaml"
  _consumer_class_label="${_consumer_class:-none}"
  run_test "consumer_routing_all_classes_unchanged_${_consumer_class_label}_result" "pass" "$(kv RESULT "$_consumer_class_out")"
  run_test "consumer_routing_all_classes_unchanged_${_consumer_class_label}_reason" "consumer_mode" "$(kv REASON "$_consumer_class_out")"
done

gate_case "type_routes_today_feature" pass type_routes_today \
  --repo-root "$REPO_ROOT" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single --type Feature

# reclassify-then-route: after the fixture re-classes the same item to
# Feature, then Bug, then Refactor, the gate routes each identically
# (pass/type_routes_today) — it never distinguishes among non-Workflow
# types, so none of the three reclassifications trip a hold this gate
# controls. The Bug scope check itself lives entirely outside this gate
# (it runs unconditionally once the gate passes), so a gate that always
# passes for Bug cannot be the thing that skips it.
gate_case "reclassify_then_route_bug" pass type_routes_today \
  --repo-root "$REPO_ROOT" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single --type Bug

gate_case "reclassify_then_route_refactor" pass type_routes_today \
  --repo-root "$REPO_ROOT" --issue 1 --status Backlog --artifact-stage '' --branch-pr-evidence none --caller single --type Refactor

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

# ===========================================================================
# Guidance mirror grep (Step 4 of the smoke runbook; named scenario
# `guidance-check-planted-violation`)
# ===========================================================================

echo ""
echo "=== guidance mirror grep: closed mirror list has no surviving Workflow guidance ==="

# Not `! rg …`: under set -e a command negated by `!` is exempt from
# errexit in bash and zsh, so that form would silently continue past a
# real violation. assert_absent captures rg's status explicitly instead.
assert_absent() {
  local label="$1"; shift
  local status=0
  rg -n "$@" >/dev/null 2>&1 || status=$?
  case "$status" in
    0) echo "  stale guidance still present: $label" >&2; return 1 ;;
    1) return 0 ;;  # no match — the only passing case
    *) echo "  rg exited $status while checking: $label" >&2; return 2 ;;
  esac
}

guidance_check_all_pass() {
  assert_absent 'agent-guidance Workflow recommendation' \
    'Use `Workflow` for' AGENTS.md CLAUDE.md GEMINI.md \
    .cursor/agents/orchestrator.md .claude/agents/orchestrator.md || return 1
  assert_absent 'retrospective create assigns Workflow' \
    'update_tracker_type_best_effort "\$ISSUE_NUMBER" "Workflow"' \
    docs/workflow/development-workflow/protocols/06-retrospective-protocol.md \
    docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md || return 1
  assert_absent 'protocol 90 route-by-brief row' \
    'route by brief: full pipeline' \
    docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md || return 1
  assert_absent 'protocol 91 route-by-brief row' \
    "Route by the brief's concrete path" \
    docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md || return 1
  assert_absent 'retrospective runbook Workflow expectation' \
    'with Type `Workflow`' \
    docs/testing/workflow/retrospective-protocol.smoke-test.md || return 1
  assert_absent 'tracker-Type runbook Workflow creation step' \
    'project Type will be set to `Workflow`' \
    docs/testing/workflow/tracker-type-field-classification.smoke-test.md || return 1
  return 0
}

cd "$REPO_ROOT"
if guidance_check_all_pass; then
  run_test "guidance_mirror_check_clean_tree_passes" "pass" "pass"
else
  run_test "guidance_mirror_check_clean_tree_passes" "pass" "fail"
fi

# guidance-check-planted-violation: re-introduce one pre-change string and
# assert the check now fails; revert and assert it passes again. A guard
# that has never failed is not known to work.
_agents_backup="$TMP_ROOT/AGENTS.md.bak"
cp "$REPO_ROOT/AGENTS.md" "$_agents_backup"
printf '\nUse `Workflow` for framework work (planted violation).\n' >> "$REPO_ROOT/AGENTS.md"
if guidance_check_all_pass; then
  run_test "guidance_check_planted_violation_detected" "fail" "pass"
else
  run_test "guidance_check_planted_violation_detected" "fail" "fail"
fi
cp "$_agents_backup" "$REPO_ROOT/AGENTS.md"

if guidance_check_all_pass; then
  run_test "guidance_check_planted_violation_reverted_passes" "pass" "pass"
else
  run_test "guidance_check_planted_violation_reverted_passes" "pass" "fail"
fi

# ===========================================================================
# Branch/PR evidence probes: local-only and origin-only ref namespaces
# (stale-backlog-open-fix-branch-no-pr-continues,
# stale-backlog-pushed-fix-branch-no-pr-continues)
# ===========================================================================

echo ""
echo "=== workflow_branch_ref_evidence / workflow_branch_pr_evidence_single_item: local-only and origin-only ref probes ==="

REF_REPO="$TMP_ROOT/ref-repo-local"
mkdir -p "$REF_REPO"
git -C "$REF_REPO" init -q
git -C "$REF_REPO" config user.email test@example.com
git -C "$REF_REPO" config user.name "Test User"
git -C "$REF_REPO" commit --allow-empty -m "initial" >/dev/null
git -C "$REF_REPO" branch fix/9002-local-only-slug >/dev/null

# stale-backlog-open-fix-branch-no-pr-continues: a live fix/ branch that
# exists ONLY as a local refs/heads/ ref — not pushed, no
# refs/remotes/origin/ ref, and no PR at all — the normal state right after
# a fast-track branch is cut. workflow-next-action.sh's own probe
# (:602-:620) is origin-only and would miss this.
local_only_ref_evidence="$(cd "$REF_REPO" && workflow_branch_ref_evidence 9002)"
run_test "stale_backlog_open_fix_branch_no_pr_continues_ref_probe" "present" "$local_only_ref_evidence"
local_only_single_item_evidence="$(cd "$REF_REPO" && workflow_branch_pr_evidence_single_item 9002 false '{"open":[],"merged":[]}')"
run_test "stale_backlog_open_fix_branch_no_pr_continues_single_item" "present" "$local_only_single_item_evidence"

REF_REPO_ORIGIN="$TMP_ROOT/ref-repo-origin"
mkdir -p "$REF_REPO_ORIGIN"
git -C "$REF_REPO_ORIGIN" init -q
git -C "$REF_REPO_ORIGIN" config user.email test@example.com
git -C "$REF_REPO_ORIGIN" config user.name "Test User"
git -C "$REF_REPO_ORIGIN" commit --allow-empty -m "initial" >/dev/null
git -C "$REF_REPO_ORIGIN" update-ref refs/remotes/origin/fix/9003-origin-only-slug HEAD

# stale-backlog-pushed-fix-branch-no-pr-continues: the same shape, but the
# branch is present ONLY as refs/remotes/origin/fix/<issue>-<slug> with no
# local ref (a fresh clone, or the local branch deleted post-push). Pins
# the other namespace: neither fixture is satisfiable by a probe that
# reads only the other.
origin_only_ref_evidence="$(cd "$REF_REPO_ORIGIN" && workflow_branch_ref_evidence 9003)"
run_test "stale_backlog_pushed_fix_branch_no_pr_continues_ref_probe" "present" "$origin_only_ref_evidence"
origin_only_single_item_evidence="$(cd "$REF_REPO_ORIGIN" && workflow_branch_pr_evidence_single_item 9003 false '{"open":[],"merged":[]}')"
run_test "stale_backlog_pushed_fix_branch_no_pr_continues_single_item" "present" "$origin_only_single_item_evidence"

REF_REPO_NONE="$TMP_ROOT/ref-repo-none"
mkdir -p "$REF_REPO_NONE"
git -C "$REF_REPO_NONE" init -q
git -C "$REF_REPO_NONE" config user.email test@example.com
git -C "$REF_REPO_NONE" config user.name "Test User"
git -C "$REF_REPO_NONE" commit --allow-empty -m "initial" >/dev/null
none_ref_evidence="$(cd "$REF_REPO_NONE" && workflow_branch_ref_evidence 9004)"
run_test "branch_ref_evidence_no_match_is_none" "none" "$none_ref_evidence"

# codex-github finding (#1583): the probe's team-prefix grammar must accept
# an alphanumeric prefix like "ab2-" (validate-workflow-branch-name.sh's
# canonical [A-Za-z][A-Za-z0-9]{0,7}-), not only the letters-only prefix
# workflow-next-action.sh:102 uses. A branch like fix/ab2-9005-slug is a
# valid team-prefixed branch under the guard and must be recognized here.
REF_REPO_ALNUM="$TMP_ROOT/ref-repo-alnum-prefix"
mkdir -p "$REF_REPO_ALNUM"
git -C "$REF_REPO_ALNUM" init -q
git -C "$REF_REPO_ALNUM" config user.email test@example.com
git -C "$REF_REPO_ALNUM" config user.name "Test User"
git -C "$REF_REPO_ALNUM" commit --allow-empty -m "initial" >/dev/null
git -C "$REF_REPO_ALNUM" branch fix/ab2-9005-alnum-prefix-slug >/dev/null
alnum_prefix_evidence="$(cd "$REF_REPO_ALNUM" && workflow_branch_ref_evidence 9005)"
run_test "branch_ref_evidence_recognizes_alphanumeric_team_prefix" "present" "$alnum_prefix_evidence"

# ===========================================================================
# End-to-end real scan -> lanes fixture (#1583). Unlike the gate-level
# scan_backlog_no_artifacts_held cases above (which call
# framework-mode-backlog-type-gate.sh directly with synthetic
# --status/--artifact-stage/--branch-pr-evidence flags), this section runs
# the REAL workflow-batch-plan.sh --scan against a real git fixture repo and
# a mocked-gh tracker read, piped into the REAL workflow-batch-lanes.sh,
# proving both scan-caller wiring points end to end:
#   - scan-backlog-no-artifacts-held (the case the feature exists for)
#   - scan-merged-implementation-pr-continues
#   - scan-status-unreadable-defers
# ===========================================================================

echo ""
echo "=== end-to-end: workflow-batch-plan.sh --scan -> workflow-batch-lanes.sh (real fixture) ==="

E2E_ROOT="$TMP_ROOT/e2e-fm-scan"
mkdir -p "$E2E_ROOT/docs/specs/developments"
cat > "$E2E_ROOT/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: github_projects
  project_number: 1
template:
  is_template: true
guardrails:
  mode: manual
YAML
git -C "$E2E_ROOT" init -q
git -C "$E2E_ROOT" config user.email test@example.com
git -C "$E2E_ROOT" config user.name "Test User"
git -C "$E2E_ROOT" commit --allow-empty -m "initial e2e fixture" >/dev/null

# Empty development folder (no spec/plan .md) for issue #9001 — the exact
# "next-action fails, no folder artifacts" shape the gate exists for. The
# leading digits of the slug (9001) are the only issue-number source since
# there is no markdown file to carry "**Issue**: #NNN".
E2E_DEV="$E2E_ROOT/docs/specs/developments/20260101000000_9001-e2e-empty-folder"
mkdir -p "$E2E_DEV"

E2E_BIN="$TMP_ROOT/e2e-mock-bin"
mkdir -p "$E2E_BIN"
cat > "$E2E_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
  exit 0
fi
if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ]; then
  case "$*" in
    *'--json owner'*) printf 'e2e-owner\n' ;;
    *'--json name'*) printf 'e2e-repo\n' ;;
    *) printf 'e2e-owner/e2e-repo\n' ;;
  esac
  exit 0
fi
if [ "${1:-}" = "api" ] && [ "${2:-}" = "graphql" ]; then
  case "$*" in
    *"projectV2(number:"*)
      printf '{"data":{"user":{"projectV2":{"id":"PVT_e2e"}}}}\n'
      ;;
    *"repository(owner:"*)
      if [ "${MOCK_E2E_ITEM_MODE:-found}" = "missing" ]; then
        printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}\n'
      else
        printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_9001","project":{"id":"PVT_e2e","number":1},"status":{"name":"Backlog"},"type":{"name":"Workflow"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}\n'
      fi
      ;;
    *)
      printf 'unexpected gh graphql call: %s\n' "$*" >&2
      exit 1
      ;;
  esac
  exit 0
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  case "$*" in
    *"--state merged"*)
      if [ "${MOCK_E2E_PR_MODE:-empty}" = "merged" ]; then
        printf '[{"number":77,"headRefName":"feature/9001-e2e-empty-folder"}]\n'
      else
        printf '[]\n'
      fi
      ;;
    *"--state open"*)
      printf '[]\n'
      ;;
    *)
      printf 'unexpected gh pr list call: %s\n' "$*" >&2
      exit 1
      ;;
  esac
  exit 0
fi
printf 'unexpected gh call: %s\n' "$*" >&2
exit 1
MOCK_GH
chmod +x "$E2E_BIN/gh"

run_e2e_scan() {
  PATH="$E2E_BIN:$PATH" WORKFLOW_SKIP_FETCH=1 AI_DEV_WORKFLOW_CONFIG_FILE="$E2E_ROOT/.ai-dev-workflow.yaml" \
    "$REPO_ROOT/scripts/development-workflow/workflow-batch-plan.sh" --repo-root "$E2E_ROOT"
}

# --- scan-backlog-no-artifacts-held, driven end to end ---
e2e_held_out="$(MOCK_E2E_ITEM_MODE=found MOCK_E2E_PR_MODE=empty run_e2e_scan)"
run_test "e2e_scan_backlog_no_artifacts_held_next_action" "hold-misclassified-type" "$(kv NEXT_ACTION "$e2e_held_out")"
e2e_held_lanes_out="$(printf '%s\n' "$e2e_held_out" | "$REPO_ROOT/scripts/development-workflow/workflow-batch-lanes.sh" --repo-root "$E2E_ROOT")"
run_test "e2e_scan_backlog_no_artifacts_held_dispatch" "held" "$(kv DISPATCH "$e2e_held_lanes_out")"

# --- scan-merged-implementation-pr-continues: same empty folder, but a
# merged implementation PR exists for the issue and no open PR/live branch.
# open_implementation_pr_metadata only lists --state open, so this fails
# unless the scan also runs the merged-PR probe. ---
e2e_merged_out="$(MOCK_E2E_ITEM_MODE=found MOCK_E2E_PR_MODE=merged run_e2e_scan)"
run_test "e2e_scan_merged_implementation_pr_continues_not_held" "no" "$(printf '%s\n' "$e2e_merged_out" | grep -q '^NEXT_ACTION=hold-misclassified-type' && echo yes || echo no)"
run_test "e2e_scan_merged_implementation_pr_continues_check" "applied" "$(kv MISCLASSIFIED_TYPE_CHECK "$e2e_merged_out")"
e2e_merged_lanes_out="$(printf '%s\n' "$e2e_merged_out" | "$REPO_ROOT/scripts/development-workflow/workflow-batch-lanes.sh" --repo-root "$E2E_ROOT")"
run_test "e2e_scan_merged_implementation_pr_continues_not_dispatch_held" "no" "$([ "$(kv DISPATCH "$e2e_merged_lanes_out")" = "held" ] && echo yes || echo no)"

# --- scan-status-unreadable-defers: tracker status read returns empty
# because the issue is not on the configured board (missing project item) —
# not the Linear-specific TRACKER_ACTION_REQUIRED signal. Proves the
# workflow-batch-plan.sh fix landed alongside this test: any empty status
# read is "unreadable" for MISCLASSIFIED_TYPE_CHECK, not only Linear's. ---
e2e_unreadable_out="$(MOCK_E2E_ITEM_MODE=missing MOCK_E2E_PR_MODE=empty run_e2e_scan)"
run_test "e2e_scan_status_unreadable_defers_not_held" "no" "$(printf '%s\n' "$e2e_unreadable_out" | grep -q '^NEXT_ACTION=hold-misclassified-type' && echo yes || echo no)"
run_test "e2e_scan_status_unreadable_defers_check" "deferred" "$(kv MISCLASSIFIED_TYPE_CHECK "$e2e_unreadable_out")"

# --- consumer-batch-plan-workflow-unchanged: the identical empty-folder
# shape under a consumer config (no template.is_template) emits no
# MISCLASSIFIED_TYPE* keys at all and never holds — this is the scenario
# that fails if the new gate call leaks into consumer mode.
#
# workflow_template_is_template (no args) resolves its config file via
# workflow_repo_root — the directory workflow-lib.sh itself lives in — not
# via --repo-root or AI_DEV_WORKFLOW_CONFIG_FILE (workflow-lib.sh:32-38;
# only workflow_effective_config_file honors the env override, and
# is_template does not call it). That is pre-existing, unrelated to #1583,
# and consistent with this repository's own single_repo assumption (plan
# Cross-Cutting Operational Assumption Check). So a consumer-mode fixture
# for this check must swap the REAL repo's .ai-dev-workflow.yaml for the
# duration of the call — passing --repo-root/--config alone does not
# change which config framework-mode reads. ---
CONSUMER_E2E_ROOT="$TMP_ROOT/e2e-consumer-scan"
mkdir -p "$CONSUMER_E2E_ROOT/docs/specs/developments"
git -C "$CONSUMER_E2E_ROOT" init -q
git -C "$CONSUMER_E2E_ROOT" config user.email test@example.com
git -C "$CONSUMER_E2E_ROOT" config user.name "Test User"
git -C "$CONSUMER_E2E_ROOT" commit --allow-empty -m "initial consumer e2e fixture" >/dev/null
mkdir -p "$CONSUMER_E2E_ROOT/docs/specs/developments/20260101000000_9001-e2e-empty-folder"

_consumer_e2e_backup="$TMP_ROOT/consumer-e2e-real-config.bak"
cp "$REPO_ROOT/.ai-dev-workflow.yaml" "$_consumer_e2e_backup"
cp "$consumer_config" "$REPO_ROOT/.ai-dev-workflow.yaml"
consumer_e2e_out="$(MOCK_E2E_ITEM_MODE=found MOCK_E2E_PR_MODE=empty PATH="$E2E_BIN:$PATH" WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-batch-plan.sh" --repo-root "$CONSUMER_E2E_ROOT")"
cp "$_consumer_e2e_backup" "$REPO_ROOT/.ai-dev-workflow.yaml"
run_test "consumer_batch_plan_workflow_unchanged_no_next_action_hold" "no" "$(printf '%s\n' "$consumer_e2e_out" | grep -q '^NEXT_ACTION=hold-misclassified-type' && echo yes || echo no)"
run_test "consumer_batch_plan_workflow_unchanged_no_misclassified_key" "no" "$(printf '%s\n' "$consumer_e2e_out" | grep -q '^MISCLASSIFIED_TYPE' && echo yes || echo no)"

# ===========================================================================
# Single-item folder resolution (#1583, prelude-issue-*): the same
# primitives run-bounded-prelude.sh's item-scope wiring composes
# (extract_github_issue_number + workflow-next-action.sh), exercised
# directly against real fixture folders rather than through the full
# run-item-scope-resolver.sh (which requires a live tracker read this test
# suite does not stand up). This proves the folder-count decision table;
# the stop/pass decision itself is covered by the gate-level tests above.
# ===========================================================================

echo ""
echo "=== single-item folder resolution: zero / one / multiple matching folders (prelude-issue-*) ==="

FOLD_ROOT="$TMP_ROOT/fold-repo"
mkdir -p "$FOLD_ROOT/docs/specs/developments"
git -C "$FOLD_ROOT" init -q
git -C "$FOLD_ROOT" config user.email test@example.com
git -C "$FOLD_ROOT" config user.name "Test User"
git -C "$FOLD_ROOT" commit --allow-empty -m "initial" >/dev/null

resolve_folder_stage() {
  local issue="$1" repo_root="$2"
  local matches=()
  while IFS= read -r folder; do
    [ -z "$folder" ] && continue
    if [ "$(extract_github_issue_number "$folder")" = "$issue" ]; then
      matches+=("$folder")
    fi
  done < <(find "$repo_root/docs/specs/developments" -mindepth 1 -maxdepth 1 -type d | sort)
  case "${#matches[@]}" in
    0) printf '' ;;
    1)
      WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" --development "${matches[0]}" --repo-root "$repo_root" 2>/dev/null \
        | awk -F= '$1=="STATUS"{print $2; exit}'
      ;;
    *) printf 'AMBIGUOUS:%s' "${#matches[@]}" ;;
  esac
}

run_test "prelude_issue_no_folder_stops_zero_matches" "" "$(resolve_folder_stage 9101 "$FOLD_ROOT")"

one_folder="$FOLD_ROOT/docs/specs/developments/20260101000000_9102-one-folder"
mkdir -p "$one_folder"
cat > "$one_folder/1_9102-one-folder_specs.md" <<'MD'
# Spec
MD
run_test "prelude_issue_one_folder_uses_its_stage" "Spec Ready" "$(resolve_folder_stage 9102 "$FOLD_ROOT")"

dup_a="$FOLD_ROOT/docs/specs/developments/20260101000000_9103-dup-a"
dup_b="$FOLD_ROOT/docs/specs/developments/20260102000000_9103-dup-b"
mkdir -p "$dup_a" "$dup_b"
run_test "prelude_issue_multiple_folders_passes_ambiguous" "AMBIGUOUS:2" "$(resolve_folder_stage 9103 "$FOLD_ROOT")"

# ===========================================================================
# Structural consumer-unchanged proofs (#1583)
# ===========================================================================

echo ""
echo "=== consumer-prelude-workflow-unchanged / consumer-next-action-workflow-unchanged ==="

# consumer-prelude-workflow-unchanged: the gate wiring block in
# run-bounded-prelude.sh is unconditionally gated on
# workflow_template_is_template = true, so it is a structural no-op in
# consumer mode (the whole block is skipped, not merely a pass-through).
run_test "consumer_prelude_workflow_unchanged_gated" "yes" "$(grep -Fq '[ "$(workflow_template_is_template)" = "true" ]' "$REPO_ROOT/scripts/development-workflow/run-bounded-prelude.sh" && echo yes || echo no)"

# consumer-next-action-workflow-unchanged: workflow-next-action.sh is not
# modified by this item at all — it carries no reference to the new gate or
# its report keys — so its NEXT_ACTION/STATUS output cannot have regressed
# in either mode. This doubles as the regression guard proving the gate was
# never wired into it.
run_test "consumer_next_action_workflow_unchanged_no_gate_reference" "no" "$(grep -qE 'framework-mode-backlog-type-gate|MISCLASSIFIED_TYPE' "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" && echo yes || echo no)"

# ===========================================================================
# Protocol 05 / 06 flow-level unavailable handling (#1583)
#   release-unavailable-continues-unsatisfied / retro-unavailable-continues-unsatisfied
# ===========================================================================

echo ""
echo "=== protocols 05/06: unavailable framework-item lookup continues the flow and is not recorded as satisfied ==="

cd "$REPO_ROOT"

release_unavailable_ok=pass
grep -Fq '**Continue** the' docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md || release_unavailable_ok=fail
grep -Fq 'release flow; state in this step' docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md || release_unavailable_ok=fail
grep -Fq 'the downstream script-bug review as satisfied — it did not run.' docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md || release_unavailable_ok=fail
run_test "release_unavailable_continues_unsatisfied" "pass" "$release_unavailable_ok"

retro_unavailable_ok=pass
grep -Fq '**Continue** the' docs/workflow/development-workflow/protocols/06-retrospective-protocol.md || retro_unavailable_ok=fail
grep -Fq 'retrospective; state that the lookup was not performed' docs/workflow/development-workflow/protocols/06-retrospective-protocol.md || retro_unavailable_ok=fail
grep -Fq 'no related item solely because the lookup was unavailable.' docs/workflow/development-workflow/protocols/06-retrospective-protocol.md || retro_unavailable_ok=fail
run_test "retro_unavailable_continues_unsatisfied" "pass" "$retro_unavailable_ok"

echo ""
echo "Test summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
