#!/usr/bin/env bash
# test-run-bounded-prelude.sh - Fixture tests for shared bounded prelude output shape.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/run-epic-policy-recommender.sh"
PRELUDE="$REPO_ROOT/scripts/development-workflow/run-bounded-prelude.sh"

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

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
