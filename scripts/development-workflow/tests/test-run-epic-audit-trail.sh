#!/usr/bin/env bash
# test-run-epic-audit-trail.sh - Unit tests for /run-epic audit comments.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HELPER="$REPO_ROOT/scripts/development-workflow/run-epic-audit-trail.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/gh-calls.log"
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"
case "$*" in
  auth\ status)
    exit 0
    ;;
  repo\ view\ --json\ nameWithOwner\ --jq\ .nameWithOwner)
    printf 'lhpaul/ai-dev-framework-template\n'
    ;;
  api\ --paginate\ --slurp\ repos/lhpaul/ai-dev-framework-template/issues/10/comments\?per_page=100)
    if [ "${MOCK_COMMENT_MODE:-missing}" = "list-fail" ]; then
      printf 'list failed\n' >&2
      exit 1
    fi
    if [ "${MOCK_COMMENT_MODE:-missing}" = "existing" ] || [ "${MOCK_COMMENT_MODE:-missing}" = "patch-fail" ]; then
      cat <<'JSON'
[[{"id":111,"body":"unrelated"}],[{"id":123,"body":"<!-- run-epic:pr-disposition -->\nold"}]]
JSON
    else
      printf '[]\n'
    fi
    ;;
  api\ --paginate\ --slurp\ repos/lhpaul/ai-dev-framework-template/issues/900/comments\?per_page=100)
    if [ "${MOCK_COMMENT_MODE:-missing}" = "list-fail" ]; then
      printf 'list failed\n' >&2
      exit 1
    fi
    if [ "${MOCK_COMMENT_MODE:-missing}" = "existing" ]; then
      cat <<'JSON'
[[{"id":456,"body":"<!-- run-epic:epic-ledger -->\nold"}]]
JSON
    else
      printf '[]\n'
    fi
    ;;
  api\ -X\ PATCH\ repos/lhpaul/ai-dev-framework-template/issues/comments/123\ --input\ -)
    if [ "${MOCK_COMMENT_MODE:-missing}" = "patch-fail" ]; then
      printf 'patch failed\n' >&2
      exit 1
    fi
    printf '{"id":123}\n'
    ;;
  api\ -X\ PATCH\ repos/lhpaul/ai-dev-framework-template/issues/comments/456\ --input\ -)
    printf '{"id":456}\n'
    ;;
  api\ -X\ POST\ repos/lhpaul/ai-dev-framework-template/issues/10/comments\ --input\ -)
    if [ "${MOCK_COMMENT_MODE:-missing}" = "post-fail" ]; then
      printf 'post failed\n' >&2
      exit 1
    fi
    printf '{"id":124}\n'
    ;;
  api\ -X\ POST\ repos/lhpaul/ai-dev-framework-template/issues/900/comments\ --input\ -)
    printf '{"id":457}\n'
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

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1" expected="$2"
  shift 2
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ] && grep -Fq -- "$expected" <<< "$output"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected failure containing '${expected}'"
    printf 'Status: %s\nOutput:\n%s\n' "$status" "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

pr_fixture="$TMP_ROOT/pr.json"
cat > "$pr_fixture" <<'JSON'
{
  "scope_source": "epic #916",
  "item": {"number": 920, "title": "Add autonomous epic audit trail"},
  "pr": {"number": 10, "head_sha": "abc123"},
  "reviewer": {"result": "clean", "blocking_count": 0, "advisory_count": 2},
  "advisories": [
    {"source": "haystack|triage", "category": "docs\nsync", "decision": "accepted", "rationale": "stale after rg verification with Authorization: dummy Bearer dummy.value"},
    {"source": "pr-agent", "category": "tests", "decision": "fixed", "rationale": ""}
  ],
  "risk": {"level": "medium", "reasons": ["workflow script change"]},
  "merge_authority": "--max-risk medium delegated by user",
  "final_decision": "merge_approved",
  "verification": {
    "labels": ["ready-for-human-review", "ready-for-regression"],
    "ci_result": "green",
    "reviewer_summary_present": true,
    "unresolved_thread_count": 0,
    "merge_state": "CLEAN",
    "issue_state": "open",
    "project_status": "In Development"
  },
  "protocol_deviations": [
    {"action": "accepted advisory", "impact": "none | expected", "mitigation": "documented\nrationale\twith ghp_FAKE_PLACEHOLDER /tmp/fake-placeholder/local"}
  ],
  "notes": "token ghp_FAKE_PLACEHOLDER /tmp/fake-placeholder/local"
}
JSON

ledger_fixture="$TMP_ROOT/ledger.json"
cat > "$ledger_fixture" <<'JSON'
{
  "epic": {"number": 916, "title": "Delegated epic orchestration"},
  "items": [
    {"issue_number": 920, "title": "Add autonomous | epic audit trail", "pr_number": 10, "tracker_status": "In Development", "risk_level": "medium", "review_result": "clean", "decision": "merge_approved", "merge_cleanup": "verified", "notes": "ready\nBearer token.value"},
    {"issue_number": 918, "title": "Add delegated review and merge loop", "tracker_status": "Backlog", "risk_level": "-", "review_result": "-", "decision": "blocked", "merge_cleanup": "-", "notes": "depends on #920"}
  ]
}
JSON

explicit_fixture="$TMP_ROOT/explicit.json"
cat > "$explicit_fixture" <<'JSON'
{"epic_not_applicable": true}
JSON

bad_advisory_fixture="$TMP_ROOT/bad-advisory.json"
jq '.advisories[0].rationale = ""' "$pr_fixture" > "$bad_advisory_fixture"
missing_pr_field_fixture="$TMP_ROOT/missing-pr-field.json"
jq 'del(.pr.head_sha)' "$pr_fixture" > "$missing_pr_field_fixture"
bad_ledger_fixture="$TMP_ROOT/bad-ledger.json"
cat > "$bad_ledger_fixture" <<'JSON'
{"epic": {"number": 916, "title": "Bad"}, "items": "not an array"}
JSON
empty_fixture="$TMP_ROOT/empty.json"
: > "$empty_fixture"
malformed_fixture="$TMP_ROOT/malformed.json"
printf '{"not": "closed"\n' > "$malformed_fixture"
missing_fixture="$TMP_ROOT/missing.json"

echo ""
echo "=== Run epic audit trail ==="

run_fails_contains "requires_known_subcommand" "unknown or missing subcommand" "$HELPER"
run_fails_contains "requires_input" "--input is required" "$HELPER" render-pr-disposition
run_fails_contains "requires_advisory_rationale" "non-fixed advisory decisions require rationale" "$HELPER" render-pr-disposition --input "$bad_advisory_fixture"
run_fails_contains "rejects_missing_pr_required_field" "missing required PR disposition fields" "$HELPER" render-pr-disposition --input "$missing_pr_field_fixture"
run_fails_contains "rejects_bad_ledger_items_type" "missing required epic ledger fields" "$HELPER" render-epic-ledger --input "$bad_ledger_fixture"
run_fails_contains "rejects_missing_input_file" "input file not found" "$HELPER" render-pr-disposition --input "$missing_fixture"
run_fails_contains "rejects_empty_input_file" "input file is empty" "$HELPER" render-pr-disposition --input "$empty_fixture"
run_fails_contains "rejects_malformed_input_json" "input file is not valid JSON" "$HELPER" render-pr-disposition --input "$malformed_fixture"

pr_output="$("$HELPER" render-pr-disposition --input "$pr_fixture")"
run_test "renders_pr_marker" "yes" "$(grep -q '<!-- run-epic:pr-disposition -->' <<< "$pr_output" && echo yes || echo no)"
run_test "renders_reviewed_sha" "yes" "$(grep -q 'abc123' <<< "$pr_output" && echo yes || echo no)"
run_test "renders_advisory_decision" "yes" "$(grep -q 'accepted' <<< "$pr_output" && echo yes || echo no)"
run_test "renders_protocol_deviation" "yes" "$(grep -q 'documented<br>rationale' <<< "$pr_output" && echo yes || echo no)"
run_test "escapes_pr_table_pipes" "yes" "$(grep -Fq 'haystack\\|triage' <<< "$pr_output" && grep -Fq 'none \\| expected' <<< "$pr_output" && echo yes || echo no)"
run_test "normalizes_pr_table_newlines_tabs" "yes" "$(grep -Fq 'docs<br>sync' <<< "$pr_output" && grep -Fq 'documented<br>rationale with' <<< "$pr_output" && echo yes || echo no)"
run_test "redacts_sensitive_values" "yes" "$(! grep -Eq 'ghp_FAKE_PLACEHOLDER|Authorization: dummy|Bearer dummy\\.value|/tmp/fake-placeholder' <<< "$pr_output" && grep -Fq 'Authorization: [REDACTED]' <<< "$pr_output" && grep -Fq 'Bearer [REDACTED]' <<< "$pr_output" && echo yes || echo no)"

ledger_output="$("$HELPER" render-epic-ledger --input "$ledger_fixture")"
run_test "renders_ledger_marker" "yes" "$(grep -q '<!-- run-epic:epic-ledger -->' <<< "$ledger_output" && echo yes || echo no)"
run_test "renders_ledger_row" "yes" "$(grep -q '#920' <<< "$ledger_output" && echo yes || echo no)"
run_test "escapes_ledger_table_pipes" "yes" "$(grep -Fq 'Add autonomous \\| epic audit trail' <<< "$ledger_output" && echo yes || echo no)"
run_test "normalizes_ledger_newlines" "yes" "$(grep -Fq 'ready<br>Bearer [REDACTED]' <<< "$ledger_output" && echo yes || echo no)"

explicit_output="$("$HELPER" render-epic-ledger --input "$explicit_fixture")"
run_test "explicit_items_skip_epic_ledger" "yes" "$(grep -q 'Not applicable' <<< "$explicit_output" && echo yes || echo no)"

create_output="$("$HELPER" apply-pr-disposition --input "$pr_fixture" --pr 10)"
run_test "creates_pr_disposition_when_missing" "CREATED_COMMENT=1" "$create_output"
update_output="$(MOCK_COMMENT_MODE=existing "$HELPER" apply-pr-disposition --input "$pr_fixture" --pr 10)"
run_test "updates_existing_pr_disposition_comment" "UPDATED_COMMENT_ID=123" "$update_output"
run_test "finds_marker_on_later_page" "yes" "$(grep -q 'PATCH repos/lhpaul/ai-dev-framework-template/issues/comments/123' "$CALL_LOG" && echo yes || echo no)"
run_test "no_duplicate_pr_comments" "1" "$(grep -c 'POST repos/lhpaul/ai-dev-framework-template/issues/10/comments' "$CALL_LOG")"
run_fails_contains "comment_list_failure_errors" "failed to read comments" env MOCK_COMMENT_MODE=list-fail "$HELPER" apply-pr-disposition --input "$pr_fixture" --pr 10
run_fails_contains "comment_post_failure_errors" "post failed" env MOCK_COMMENT_MODE=post-fail "$HELPER" apply-pr-disposition --input "$pr_fixture" --pr 10
run_fails_contains "comment_patch_failure_errors" "patch failed" env MOCK_COMMENT_MODE=patch-fail "$HELPER" apply-pr-disposition --input "$pr_fixture" --pr 10

ledger_create_output="$("$HELPER" apply-epic-ledger --input "$ledger_fixture" --epic 900)"
run_test "creates_epic_ledger_when_missing" "CREATED_COMMENT=1" "$ledger_create_output"
ledger_update_output="$(MOCK_COMMENT_MODE=existing "$HELPER" apply-epic-ledger --input "$ledger_fixture" --epic 900)"
run_test "updates_existing_epic_ledger_comment" "UPDATED_COMMENT_ID=456" "$ledger_update_output"

run_test "uses_json_input_for_comments" "yes" "$(grep -q -- '--input -' "$CALL_LOG" && echo yes || echo no)"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
