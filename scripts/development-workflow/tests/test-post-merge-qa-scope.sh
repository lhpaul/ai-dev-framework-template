#!/usr/bin/env bash
# test-post-merge-qa-scope.sh — unit tests for post-merge-qa-scope.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/post-merge-qa-scope.sh"
NO_TRACKER_CONFIG="$SCRIPT_DIR/fixtures/post-merge-qa-tracker-none.yaml"

PASS_COUNT=0
FAIL_COUNT=0
TMP_ROOT="$(mktemp -d)" || {
  echo "Failed to create test temp dir" >&2
  exit 1
}
trap 'rm -rf "$TMP_ROOT"' EXIT

DOWNSTREAM_ROOT="$TMP_ROOT/downstream"
DOWNSTREAM_HELPER="$DOWNSTREAM_ROOT/scripts/development-workflow/post-merge-qa-scope.sh"

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1" needle="$2"
  shift 2
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ] && grep -Fq -- "$needle" <<<"$output"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected failure containing '$needle' (status $status)"
    printf '%s\n' "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

MOCK_BIN="$TMP_ROOT/bin"
mkdir -p "$MOCK_BIN"
cat >"$MOCK_BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"pr list"*"--base develop-empty"*)
    echo '[]'
    ;;
  *"pr list"*"--state merged"*)
    # Include a malformed row to verify skip-and-continue behavior
    cat <<'JSON'
[{"number":101,"title":"Merged feature","url":"https://example.test/pr/101","mergedAt":"2026-07-01T00:00:00Z","headRefName":"fix/51-merged-feature","body":"Implements #51"},{"number":null,"title":"Bad","url":"https://example.test/pr/bad"}]
JSON
    ;;
  *"issue view"*"--json"*)
    # last numeric arg-ish — parse issue number from args
    issue=""
    for a in "$@"; do
      if [[ "$a" =~ ^[0-9]+$ ]]; then issue="$a"; fi
    done
    if [ "$issue" = "999001" ]; then
      echo "issue not found" >&2
      exit 1
    fi
    if [ "$issue" = "50" ]; then
      cat <<'JSON'
{"number":50,"title":"Epic","url":"https://example.test/issues/50","labels":[{"name":"integration-branch:demo"}],"body":"epic"}
JSON
    else
      cat <<JSON
{"number":${issue:-1},"title":"Issue ${issue:-1}","url":"https://example.test/issues/${issue:-1}","labels":[],"body":""}
JSON
    fi
    ;;
  *"issue list"*"integration-branch:demo"*)
    if [ "$FAIL_INTEGRATION_ISSUE_LIST" = "1" ]; then
      echo "integration issue query failed" >&2
      exit 1
    fi
    cat <<'JSON'
[{"number":50,"title":"Epic","url":"https://example.test/issues/50"},{"number":51,"title":"Child","url":"https://example.test/issues/51"}]
JSON
    ;;
  *)
    echo "unexpected gh: $*" >&2
    exit 99
    ;;
esac
STUB
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"
export FAIL_INTEGRATION_ISSUE_LIST=""

mkdir -p "$(dirname -- "$DOWNSTREAM_HELPER")"
cp "$HELPER" "$DOWNSTREAM_HELPER"
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" "$(dirname -- "$DOWNSTREAM_HELPER")/workflow-lib.sh"

run_fails_contains "requires_base" "--base is required" "$HELPER" --json
run_fails_contains "requires_base_value" "--base requires a value" "$HELPER" --base --json
run_fails_contains "rejects_feature_base" "Disallowed base" "$HELPER" --base feature/foo --json
run_fails_contains "rejects_bad_recent" "--recent-merged-prs must be" "$HELPER" --base develop --recent-merged-prs no --json
run_fails_contains "requires_epic_value" "--epic requires a value" "$HELPER" --base develop --epic --json
run_fails_contains "requires_issues_value" "--issues requires a value" "$HELPER" --base develop --issues --json
run_fails_contains "requires_tracker_items_value" "--tracker-items requires a value" "$HELPER" --base develop --tracker-items --json
run_fails_contains "requires_recent_value" "--recent-merged-prs requires a value" "$HELPER" --base develop --recent-merged-prs --json

out="$("$HELPER" --base develop --recent-merged-prs 1 --json)" || {
  echo "FAIL: recent_merged helper exited non-zero"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  out="{}"
}
run_test "recent_merged_count" "1" "$(printf '%s' "$out" | jq -er '.candidateCount')"
run_test "confirmation_required" "true" "$(printf '%s' "$out" | jq -er '.confirmationRequired')"
run_test "read_only_present" "yes" "$(printf '%s' "$out" | jq -er 'if .readOnlyGuarantee then "yes" else "no" end')"
run_test "base_echoed" "develop" "$(printf '%s' "$out" | jq -er '.base')"
run_test "recent_merged_scope_source" "explicit" "$(printf '%s' "$out" | jq -er '.scopeSource')"
run_test "recent_merged_is_not_fallback" "false" "$(printf '%s' "$out" | jq -er '.fallback')"

out_tracker_required="$("$HELPER" --base develop --json)" || {
  echo "FAIL: configured tracker helper exited non-zero"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  out_tracker_required="{}"
}
run_test "configured_tracker_requires_discovery" "0" "$(printf '%s' "$out_tracker_required" | jq -er '.candidateCount')"
run_test "configured_tracker_scope_source" "tracker-post-merge" "$(printf '%s' "$out_tracker_required" | jq -er '.scopeSource')"
run_test "configured_tracker_is_not_fallback" "false" "$(printf '%s' "$out_tracker_required" | jq -er '.fallback')"
run_test "configured_tracker_is_not_confirmable" "false" "$(printf '%s' "$out_tracker_required" | jq -er '.confirmationRequired')"
run_test "configured_tracker_requires_discovery_flag" "true" "$(printf '%s' "$out_tracker_required" | jq -er '.discoveryRequired')"

out_explicit_empty="$("$HELPER" --base develop-empty --recent-merged-prs 1 --json)" || {
  echo "FAIL: explicit empty helper exited non-zero"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  out_explicit_empty="{}"
}
run_test "explicit_empty_scope_remains_confirmable" "true" "$(printf '%s' "$out_explicit_empty" | jq -er '.confirmationRequired')"
run_test "explicit_empty_scope_does_not_require_discovery" "false" "$(printf '%s' "$out_explicit_empty" | jq -er '.discoveryRequired')"

out_no_tracker="$(AI_DEV_WORKFLOW_CONFIG_FILE="$NO_TRACKER_CONFIG" "$HELPER" --base develop --json)" || {
  echo "FAIL: no-tracker override helper exited non-zero"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  out_no_tracker="{}"
}
run_test "no_tracker_override_uses_pr_fallback" "merged-prs" "$(printf '%s' "$out_no_tracker" | jq -er '.scopeSource')"
run_test "no_tracker_override_is_fallback" "true" "$(printf '%s' "$out_no_tracker" | jq -er '.fallback')"

out_no_config="$(cd "$DOWNSTREAM_ROOT" && "$DOWNSTREAM_HELPER" --base develop --json)" || {
  echo "FAIL: no-config helper exited non-zero"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  out_no_config="{}"
}
run_test "no_config_uses_pr_fallback" "merged-prs" "$(printf '%s' "$out_no_config" | jq -er '.scopeSource')"
run_test "no_config_is_not_provider_backed" "false" "$(printf '%s' "$out_no_config" | jq -er '.providerBacked')"
run_test "no_config_is_fallback" "true" "$(printf '%s' "$out_no_config" | jq -er '.fallback')"

out2="$("$HELPER" --base develop --issues 42 --json)" || {
  echo "FAIL: explicit_issue helper exited non-zero"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  out2="{}"
}
run_test "explicit_issue" "42" "$(printf '%s' "$out2" | jq -er '.candidates[0].number')"
run_test "explicit_scope_source" "explicit" "$(printf '%s' "$out2" | jq -er '.scopeSource')"

out_tracker="$("$HELPER" --base develop --tracker-items LEA-223,LEA-224 --json)" || {
  echo "FAIL: tracker_items helper exited non-zero"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  out_tracker="{}"
}
run_test "tracker_items_count" "2" "$(printf '%s' "$out_tracker" | jq -er '.candidateCount')"
run_test "tracker_item_id" "LEA-223" "$(printf '%s' "$out_tracker" | jq -er '.candidates[0].id')"
run_test "tracker_scope_source" "tracker-post-merge" "$(printf '%s' "$out_tracker" | jq -er '.scopeSource')"
run_test "tracker_is_provider_backed" "true" "$(printf '%s' "$out_tracker" | jq -er '.providerBacked')"
out_tracker_text="$("$HELPER" --base develop --tracker-items LEA-223)" || {
  echo "FAIL: tracker_items text helper exited non-zero"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  out_tracker_text=""
}
if grep -Fq -- "[tracker_item #LEA-223]" <<<"$out_tracker_text"; then
  tracker_text_present="yes"
else
  tracker_text_present="no"
fi
run_test "tracker_item_text_id" "yes" "$tracker_text_present"

out3="$("$HELPER" --base develop-demo --epic 50 --json)" || {
  echo "FAIL: epic helper exited non-zero"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  out3="{}"
}
run_test "epic_child_included" "yes" "$(printf '%s' "$out3" | jq -er 'any(.candidates[]; .number == 51) | if . then "yes" else "no" end')"
run_test "epic_self_excluded" "no" "$(printf '%s' "$out3" | jq -er 'any(.candidates[]; .number == 50) | if . then "yes" else "no" end')"
run_test "epic_scope_source" "epic" "$(printf '%s' "$out3" | jq -er '.scopeSource')"
run_test "epic_merged_pr_included" "yes" "$(printf '%s' "$out3" | jq -er 'any(.candidates[]; .kind == "pull_request" and .number == 101) | if . then "yes" else "no" end')"

out_integration="$("$HELPER" --base develop-demo --json)" || {
  echo "FAIL: integration helper exited non-zero"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  out_integration="{}"
}
run_test "integration_scope_source" "integration-branch" "$(printf '%s' "$out_integration" | jq -er '.scopeSource')"
run_test "integration_default_includes_labelled_issue" "yes" "$(printf '%s' "$out_integration" | jq -er 'any(.candidates[]; .kind == "issue" and .number == 51) | if . then "yes" else "no" end')"
run_test "integration_default_excludes_unmerged_labelled_issue" "no" "$(printf '%s' "$out_integration" | jq -er 'any(.candidates[]; .kind == "issue" and .number == 50) | if . then "yes" else "no" end')"
run_test "integration_default_includes_merged_pr" "yes" "$(printf '%s' "$out_integration" | jq -er 'any(.candidates[]; .kind == "pull_request" and .number == 101) | if . then "yes" else "no" end')"

out_integration_fallback="$(FAIL_INTEGRATION_ISSUE_LIST=1 "$HELPER" --base develop-demo --json)" || {
  echo "FAIL: degraded integration helper exited non-zero"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  out_integration_fallback="{}"
}
run_test "degraded_integration_uses_pr_fallback" "merged-prs" "$(printf '%s' "$out_integration_fallback" | jq -er '.scopeSource')"
run_test "degraded_integration_is_fallback" "true" "$(printf '%s' "$out_integration_fallback" | jq -er '.fallback')"

run_fails_contains "rejects_invalid_issues" "Invalid issue in --issues" "$HELPER" --base develop --issues "abc" --json
run_fails_contains "rejects_invalid_tracker_items" "Invalid tracker item in --tracker-items" "$HELPER" --base develop --tracker-items "bad/item" --json
run_fails_contains "rejects_missing_issue" "Failed to read issue" "$HELPER" --base develop --issues "999001" --json

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
