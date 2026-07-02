#!/usr/bin/env bash
# test-run-bounded-prelude.sh - Fixture tests for shared bounded prelude output shape.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/run-epic-policy-recommender.sh"
PRELUDE="$REPO_ROOT/scripts/development-workflow/run-bounded-prelude.sh"
ITEM_RESOLVER="$REPO_ROOT/scripts/development-workflow/run-item-scope-resolver.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass=0
fail=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
    printf 'ok %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL %s expected=%s actual=%s\n' "$name" "$expected" "$actual"
  fi
}

write_fixture() {
  local name="$1" json="$2"
  local path="$TMP_ROOT/${name}.json"
  printf '%s\n' "$json" >"$path"
  printf '%s\n' "$path"
}

item_scope='{
  "scopeSource": "item",
  "epicNumber": null,
  "itemInput": "1049",
  "resolvedIssueNumber": 1049,
  "baseBranch": "develop-orchestration-command-refactor",
  "baseAmbiguous": false,
  "baseReason": "shared integration branch label",
  "policy": {"delegateReview": false, "mayMerge": false, "mayStartBacklog": false, "maxRisk": "low"},
  "groups": {
    "eligible": [{"number": 1049, "title": "Shared bounded prelude", "status": "Backlog", "type": "Workflow", "labels": [], "body": "workflow orchestration"}],
    "blocked": [], "already_merged": [], "in_review": [], "ambiguous": [], "out_of_scope": []
  },
  "items": [{"number": 1049, "title": "Shared bounded prelude", "status": "Backlog", "type": "Workflow", "labels": [], "body": "workflow orchestration"}]
}'

item_fixture="$(write_fixture item-scope "$item_scope")"
policy_out="$(AI_DEV_WORKFLOW_CONFIG_FILE="$REPO_ROOT/.ai-dev-workflow.yaml" \
  "$HELPER" --scope "$item_fixture" --original-command "/run-item 1049" \
  --delegate-review --may-merge --may-start-backlog true --max-risk medium --json)"

run_test "item_policy_copy_paste" "true" "$(printf '%s\n' "$policy_out" | jq -r '(.copyPasteCommand | test("/run-item 1049"))')"
run_test "item_policy_delegate" "true" "$(printf '%s\n' "$policy_out" | jq -r '.effectivePolicy.delegateReview')"

run_test "prelude_help" "0" "$( "$PRELUDE" --help >/dev/null; echo 0)"

run_fails() {
  local name="$1" expected="$2"
  shift 2
  set +e
  local out status
  out="$("$@" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ] && grep -Fq -- "$expected" <<<"$out"; then
    pass=$((pass + 1))
    printf 'ok %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL %s status=%s\n%s\n' "$name" "$status" "$out"
  fi
}

run_fails "reject_epic_and_issue" "not --epic with item flags" \
  "$PRELUDE" --original-command "/run-item 1" --epic 1047 --issue 1049
run_fails "reject_multiple_item_flags" "exactly one item target flag" \
  "$PRELUDE" --original-command "/run-item 1" --issue 1049 --branch feature/1049-x

guardrails_config="$TMP_ROOT/ai-dev-workflow-linear-guardrails.yaml"
cat > "$guardrails_config" <<'YAML'
schema_version: 2
review:
  on_draft:
    runner:
      - codex
issue_tracker:
  provider: linear
guardrails:
  mode: assisted
  backlog_start:
    allow_without_confirmation: true
  stages:
    spec:
      may_open_pr: true
      may_merge_pr: false
      max_merge_risk: low
    plan:
      may_open_pr: true
      may_merge_pr: false
      max_merge_risk: low
    implementation:
      may_open_pr: true
      may_merge_pr: false
      max_merge_risk: low
YAML

github_config="$TMP_ROOT/ai-dev-workflow-github.yaml"
cat > "$github_config" <<'YAML'
schema_version: 2
issue_tracker:
  provider: github_projects
YAML

absent_guardrails_config="$TMP_ROOT/ai-dev-workflow-linear-no-guardrails.yaml"
cat > "$absent_guardrails_config" <<'YAML'
schema_version: 2
review:
  on_draft:
    runner:
      - codex
issue_tracker:
  provider: linear
YAML

linear_prelude_out="$(AI_DEV_WORKFLOW_CONFIG_FILE="$guardrails_config" \
  "$PRELUDE" --original-command "/run-item LEA-185" --issue LEA-185 --json)"
run_test "linear_issue_identifier_resolves" "LEA-185" "$(printf '%s\n' "$linear_prelude_out" | jq -r '.scope.resolvedIssueIdentifier')"
run_test "guardrails_section_present" "present" "$(printf '%s\n' "$linear_prelude_out" | jq -r '.guardrails.section')"
run_test "guardrails_backlog_start_applied" "true" "$(printf '%s\n' "$linear_prelude_out" | jq -r '.policyRecommendation.effectivePolicy.mayStartBacklog')"
run_test "guardrails_merge_stays_false" "false" "$(printf '%s\n' "$linear_prelude_out" | jq -r '.policyRecommendation.effectivePolicy.mayMerge')"
run_test "guardrails_implementation_merge_reported" "false" "$(printf '%s\n' "$linear_prelude_out" | jq -r '.guardrails.stages.implementation.may_merge_pr')"

linear_target_prelude_out="$(AI_DEV_WORKFLOW_CONFIG_FILE="$guardrails_config" \
  "$PRELUDE" --original-command "/run-item LEA-185" --target LEA-185 --json)"
run_test "linear_target_identifier_resolves" "LEA-185" "$(printf '%s\n' "$linear_target_prelude_out" | jq -r '.scope.resolvedIssueIdentifier')"

linear_resolver_text="$(AI_DEV_WORKFLOW_CONFIG_FILE="$guardrails_config" \
  "$ITEM_RESOLVER" --issue LEA-185)"
run_test "linear_resolver_text_defers_tracker" "true" "$(grep -q 'TRACKER_READ_DEFERRED=yes' <<<"$linear_resolver_text" && echo true || echo false)"

linear_resolver_json="$(AI_DEV_WORKFLOW_CONFIG_FILE="$guardrails_config" \
  "$ITEM_RESOLVER" --issue LEA-185 --json)"
run_test "linear_resolver_json_defers_tracker" "true" "$(printf '%s\n' "$linear_resolver_json" | jq -r '.trackerReadDeferred')"
run_test "linear_resolver_json_uses_backlog_placeholder" "Backlog" "$(printf '%s\n' "$linear_resolver_json" | jq -r '.items[0].status')"

linear_target_json="$(AI_DEV_WORKFLOW_CONFIG_FILE="$guardrails_config" \
  "$ITEM_RESOLVER" --target LEA-185 --json)"
run_test "linear_target_json_defers_tracker" "true" "$(printf '%s\n' "$linear_target_json" | jq -r '.trackerReadDeferred')"

absent_guardrails_out="$(AI_DEV_WORKFLOW_CONFIG_FILE="$absent_guardrails_config" \
  "$PRELUDE" --original-command "/run-item LEA-185" --issue LEA-185 --json)"
run_test "absent_guardrails_section_reported" "absent" "$(printf '%s\n' "$absent_guardrails_out" | jq -r '.guardrails.section')"
run_test "absent_guardrails_backlog_default_applied" "false" "$(printf '%s\n' "$absent_guardrails_out" | jq -r '.policyRecommendation.effectivePolicy.mayStartBacklog')"
run_test "absent_guardrails_review_default_applied" "false" "$(printf '%s\n' "$absent_guardrails_out" | jq -r '.policyRecommendation.effectivePolicy.delegateReview')"
run_test "absent_guardrails_merge_default_applied" "false" "$(printf '%s\n' "$absent_guardrails_out" | jq -r '.policyRecommendation.effectivePolicy.mayMerge')"
run_test "absent_guardrails_risk_default_applied" "low" "$(printf '%s\n' "$absent_guardrails_out" | jq -r '.policyRecommendation.effectivePolicy.maxRisk')"

run_fails "reject_linear_identifier_with_underscore" "invalid --issue identifier" \
  env AI_DEV_WORKFLOW_CONFIG_FILE="$guardrails_config" "$ITEM_RESOLVER" --issue A_B-123
run_fails "reject_whitespace_issue_identifier" "invalid --issue identifier" \
  env AI_DEV_WORKFLOW_CONFIG_FILE="$guardrails_config" "$ITEM_RESOLVER" --issue "   "
run_fails "reject_linear_identifier_for_non_linear_provider" "invalid --issue identifier" \
  env AI_DEV_WORKFLOW_CONFIG_FILE="$github_config" "$ITEM_RESOLVER" --issue LEA-185

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
