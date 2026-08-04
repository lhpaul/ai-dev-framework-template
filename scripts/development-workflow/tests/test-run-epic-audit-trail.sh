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
  api\ --paginate\ --slurp\ repos/lhpaul/ai-dev-framework-template/issues/42/comments\?per_page=100)
    if [ "${MOCK_COMMENT_MODE:-missing}" = "existing-bypass" ]; then
      cat <<'JSON'
[[{"id":789,"body":"<!-- reviewer-access-bypass -->\nold"}]]
JSON
    else
      printf '[]\n'
    fi
    ;;
  api\ -X\ PATCH\ repos/lhpaul/ai-dev-framework-template/issues/comments/123\ --input\ -)
    cat >/dev/null || true
    if [ "${MOCK_COMMENT_MODE:-missing}" = "patch-fail" ]; then
      printf 'patch failed\n' >&2
      exit 1
    fi
    printf '{"id":123}\n'
    ;;
  api\ -X\ PATCH\ repos/lhpaul/ai-dev-framework-template/issues/comments/456\ --input\ -)
    cat >/dev/null || true
    printf '{"id":456}\n'
    ;;
  api\ -X\ PATCH\ repos/lhpaul/ai-dev-framework-template/issues/comments/789\ --input\ -)
    cat >/dev/null || true
    printf '{"id":789}\n'
    ;;
  api\ -X\ POST\ repos/lhpaul/ai-dev-framework-template/issues/10/comments\ --input\ -)
    cat >/dev/null || true
    if [ "${MOCK_COMMENT_MODE:-missing}" = "post-fail" ]; then
      printf 'post failed\n' >&2
      exit 1
    fi
    printf '{"id":124}\n'
    ;;
  api\ -X\ POST\ repos/lhpaul/ai-dev-framework-template/issues/900/comments\ --input\ -)
    cat >/dev/null || true
    printf '{"id":457}\n'
    ;;
  api\ -X\ POST\ repos/lhpaul/ai-dev-framework-template/issues/42/comments\ --input\ -)
    cat >/dev/null || true
    printf '{"id":790}\n'
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
  "pr": {"number": 10, "head_sha": "abc123", "branch": "implementation-plan/audit-trail"},
  "reviewer": {"result": "clean", "blocking_count": 0, "advisory_count": 2},
  "advisories": [
    {"source": "haystack|triage", "category": "docs\nsync", "decision": "accepted", "rationale": "stale after rg verification with Authorization: dummy Bearer dummy.value"},
    {"source": "pr-agent", "category": "tests", "decision": "fixed", "rationale": ""}
  ],
  "risk": {"level": "medium", "reasons": ["workflow script change"]},
  "merge_authority": "--max-risk medium delegated by user",
  "final_decision": "merge_approved",
  "invocation_policy": {
    "original_command": "$run-epic issues 920 /tmp/fake-placeholder/local",
    "copy_paste_command": "$run-epic --items 920 --delegate-review --may-merge --may-start-backlog true --max-risk medium --base develop-delegated-epic-orchestration",
    "confirmation": "accepted recommended policy",
    "recommended_policy": {
      "mayStartBacklog": true,
      "delegateReview": true,
      "mayMerge": true,
      "maxRisk": "medium",
      "base": "develop-delegated-epic-orchestration"
    },
    "selected_policy": {
      "mayStartBacklog": true,
      "delegateReview": true,
      "mayMerge": true,
      "maxRisk": "medium",
      "base": "develop-delegated-epic-orchestration"
    },
    "effective_policy": {
      "mayStartBacklog": true,
      "delegateReview": true,
      "mayMerge": true,
      "maxRisk": "medium",
      "base": "develop-delegated-epic-orchestration"
    }
  },
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
  "checkpoint_policy": {
    "field_source": "recommended",
    "recommended": [
      {
        "item_number": 920,
        "stage": "plan",
        "domain": "technical",
        "reason": "schema signals",
        "required_human_action": "approve data model",
        "satisfaction_state": "pending"
      }
    ],
    "selected": [
      {
        "item_number": 920,
        "stage": "plan",
        "domain": "technical",
        "reason": "schema signals",
        "required_human_action": "approve data model",
        "satisfaction_state": "pending"
      }
    ],
    "effective": [
      {
        "item_number": 920,
        "stage": "plan",
        "domain": "technical",
        "reason": "schema signals",
        "required_human_action": "approve data model",
        "satisfaction_state": "satisfied",
        "satisfied_by": "human-reviewer"
      }
    ]
  },
  "notes": "token ghp_FAKE_PLACEHOLDER /tmp/fake-placeholder/local"
}
JSON

ledger_fixture="$TMP_ROOT/ledger.json"
cat > "$ledger_fixture" <<'JSON'
{
  "epic": {"number": 916, "title": "Delegated epic orchestration"},
  "invocation_policy": {
    "effective_policy": {
      "mayStartBacklog": true,
      "delegateReview": true,
      "mayMerge": true,
      "maxRisk": "medium",
      "base": "develop-delegated-epic-orchestration"
    }
  },
  "items": [
    {"issue_number": 920, "title": "Add autonomous | epic audit trail", "pr_number": 10, "tracker_status": "In Development", "risk_level": "medium", "review_result": "clean", "decision": "merge_approved", "merge_cleanup": "verified", "notes": "ready\nBearer token.value", "checkpoints": [{"item_number": 920, "stage": "plan", "domain": "technical", "satisfaction_state": "satisfied"}]},
    {"issue_number": 918, "title": "Add delegated review and merge loop", "tracker_status": "Backlog", "risk_level": "-", "review_result": "-", "decision": "blocked", "merge_cleanup": "-", "notes": "depends on #920", "stop_gate": "blocked dependency"}
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
legacy_policy_fixture="$TMP_ROOT/legacy-policy.json"
jq 'del(.invocation_policy)' "$pr_fixture" > "$legacy_policy_fixture"
bad_ledger_fixture="$TMP_ROOT/bad-ledger.json"
cat > "$bad_ledger_fixture" <<'JSON'
{"epic": {"number": 916, "title": "Bad"}, "items": "not an array"}
JSON
bypass_fixture="$TMP_ROOT/reviewer-access-bypass.json"
cat > "$bypass_fixture" <<'JSON'
{
  "state": "authorized_pending_attempt",
  "authorization": {
    "authorized_by": "lhpaul",
    "authorized_at": "2026-07-29T12:00:00Z",
    "authorization_text": "Approve gh pr merge 42 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa for ghp_FAKE_PLACEHOLDER"
  },
  "pr": {
    "number": 42,
    "head_sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "evidence_fingerprint": "sha256:abc123",
  "ci": {
    "result": "green"
  },
  "reviewer": {
    "result": "clean",
    "blocking_count": 0
  },
  "blocked_check": {
    "name": "Haystack / Review",
    "state": "failure"
  },
  "access": {
    "evidence": "HTTP 403 from /Users/lhpaul/private/url",
    "remediation_status": "org approval requested",
    "bypass_reason": "release window cannot wait for org approval"
  },
  "proposed_action": "gh pr merge 42 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "attempt": {
    "result": "not_attempted",
    "exit_code": "",
    "live_pr_state": "open"
  }
}
JSON
bad_bypass_fixture="$TMP_ROOT/bad-bypass.json"
jq 'del(.authorization.authorized_by)' "$bypass_fixture" > "$bad_bypass_fixture"
mismatched_bypass_pr_fixture="$TMP_ROOT/mismatched-bypass-pr.json"
jq '.pr.number = 99' "$bypass_fixture" > "$mismatched_bypass_pr_fixture"
mismatched_bypass_action_fixture="$TMP_ROOT/mismatched-bypass-action.json"
jq '.proposed_action = "gh pr merge 99 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$bypass_fixture" > "$mismatched_bypass_action_fixture"
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
run_fails_contains "rejects_missing_bypass_required_field" "missing required reviewer access-bypass fields: authorization.authorized_by" "$HELPER" render-reviewer-access-bypass --input "$bad_bypass_fixture"
run_fails_contains "rejects_mismatched_bypass_pr_on_apply" "reviewer access-bypass input must target PR #42" "$HELPER" apply-reviewer-access-bypass --input "$mismatched_bypass_pr_fixture" --pr 42
run_fails_contains "rejects_mismatched_bypass_action_on_apply" "proposed action 'gh pr merge 42 --admin --match-head-commit <head-sha>'" "$HELPER" apply-reviewer-access-bypass --input "$mismatched_bypass_action_fixture" --pr 42
run_fails_contains "rejects_missing_input_file" "input file not found" "$HELPER" render-pr-disposition --input "$missing_fixture"
run_fails_contains "rejects_empty_input_file" "input file is empty" "$HELPER" render-pr-disposition --input "$empty_fixture"
run_fails_contains "rejects_malformed_input_json" "input file is not valid JSON" "$HELPER" render-pr-disposition --input "$malformed_fixture"

pr_output="$("$HELPER" render-pr-disposition --input "$pr_fixture")"
run_test "renders_pr_marker" "yes" "$(grep -q '<!-- run-epic:pr-disposition -->' <<< "$pr_output" && echo yes || echo no)"
run_test "renders_reviewed_sha" "yes" "$(grep -q 'abc123' <<< "$pr_output" && echo yes || echo no)"
run_test "renders_advisory_decision" "yes" "$(grep -q 'accepted' <<< "$pr_output" && echo yes || echo no)"
run_test "renders_protocol_deviation" "yes" "$(grep -q 'documented<br>rationale' <<< "$pr_output" && echo yes || echo no)"
run_test "renders_invocation_policy" "yes" "$(grep -q '### Invocation Policy' <<< "$pr_output" && grep -q 'accepted recommended policy' <<< "$pr_output" && echo yes || echo no)"
run_test "renders_policy_table" "yes" "$(grep -q '| mayStartBacklog | true | true | true |' <<< "$pr_output" && grep -q '| maxRisk | medium | medium | medium |' <<< "$pr_output" && echo yes || echo no)"
run_test "renders_checkpoint_policy" "yes" "$(grep -q '### Checkpoint Policy' <<< "$pr_output" && grep -q 'approve data model' <<< "$pr_output" && echo yes || echo no)"
run_test "pending_checkpoint_count_excludes_satisfied" "0" "$(printf '%s\n' "$pr_output" | grep 'Pending applicable checkpoints:' | sed 's/.*: //')"

stage_scoped_fixture="$TMP_ROOT/stage-scoped-checkpoints.json"
jq '.checkpoint_policy.effective = [
  {"item_number": 920, "stage": "plan", "domain": "technical", "reason": "plan pending", "required_human_action": "approve plan", "satisfaction_state": "pending"},
  {"item_number": 920, "stage": "implementation", "domain": "technical", "reason": "impl pending", "required_human_action": "approve impl", "satisfaction_state": "pending"}
] | .pr.branch = "implementation-plan/audit-trail"' "$pr_fixture" > "$stage_scoped_fixture"
stage_scoped_output="$("$HELPER" render-pr-disposition --input "$stage_scoped_fixture")"
run_test "pending_count_scoped_to_pr_stage" "1" "$(printf '%s\n' "$stage_scoped_output" | grep 'Pending applicable checkpoints:' | sed 's/.*: //')"
run_test "escapes_pr_table_pipes" "yes" "$(grep -Fq 'haystack\\|triage' <<< "$pr_output" && grep -Fq 'none \\| expected' <<< "$pr_output" && echo yes || echo no)"
run_test "normalizes_pr_table_newlines_tabs" "yes" "$(grep -Fq 'docs<br>sync' <<< "$pr_output" && grep -Fq 'documented<br>rationale with' <<< "$pr_output" && echo yes || echo no)"
run_test "redacts_sensitive_values" "yes" "$(! grep -Eq 'ghp_FAKE_PLACEHOLDER|Authorization: dummy|Bearer dummy\\.value|/tmp/fake-placeholder' <<< "$pr_output" && grep -Fq 'Authorization: [REDACTED]' <<< "$pr_output" && grep -Fq 'Bearer [REDACTED]' <<< "$pr_output" && echo yes || echo no)"

legacy_policy_output="$("$HELPER" render-pr-disposition --input "$legacy_policy_fixture")"
run_test "legacy_pr_disposition_policy_optional" "yes" "$(grep -q 'Not recorded' <<< "$legacy_policy_output" && echo yes || echo no)"

ledger_output="$("$HELPER" render-epic-ledger --input "$ledger_fixture")"
run_test "renders_ledger_marker" "yes" "$(grep -q '<!-- run-epic:epic-ledger -->' <<< "$ledger_output" && echo yes || echo no)"
run_test "renders_ledger_row" "yes" "$(grep -q '#920' <<< "$ledger_output" && echo yes || echo no)"
run_test "escapes_ledger_table_pipes" "yes" "$(grep -Fq 'Add autonomous \\| epic audit trail' <<< "$ledger_output" && echo yes || echo no)"
run_test "normalizes_ledger_newlines" "yes" "$(grep -Fq 'ready<br>Bearer [REDACTED]' <<< "$ledger_output" && echo yes || echo no)"
run_test "ledger_notes_include_effective_policy" "yes" "$(grep -Fq 'Effective policy: mayStartBacklog=true, delegateReview=true, mayMerge=true, maxRisk=medium, base=develop-delegated-epic-orchestration' <<< "$ledger_output" && echo yes || echo no)"
run_test "ledger_notes_include_stop_gate" "yes" "$(grep -Fq 'Stop gate: blocked dependency' <<< "$ledger_output" && echo yes || echo no)"
run_test "ledger_notes_include_checkpoints" "yes" "$(grep -Fq 'Checkpoints: #920 plan/technical=satisfied' <<< "$ledger_output" && echo yes || echo no)"

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

ledger_root_checkpoint_fixture="$TMP_ROOT/ledger-root-checkpoints.json"
cat > "$ledger_root_checkpoint_fixture" <<'JSON'
{
  "epic": {"number": 916, "title": "Delegated epic orchestration"},
  "invocation_policy": {
    "effective_policy": {
      "mayStartBacklog": true,
      "delegateReview": true,
      "mayMerge": true,
      "maxRisk": "medium",
      "base": "develop-delegated-epic-orchestration",
      "checkpoints": [
        {"item_number": 920, "stage": "plan", "domain": "technical", "satisfaction_state": "pending"},
        {"item_number": 918, "stage": "plan", "domain": "technical", "satisfaction_state": "pending"}
      ]
    }
  },
  "items": [
    {"issue_number": 920, "title": "Item A", "tracker_status": "In Development", "decision": "merge_approved"},
    {"issue_number": 918, "title": "Item B", "tracker_status": "Backlog", "decision": "blocked"}
  ]
}
JSON
root_checkpoint_ledger_output="$("$HELPER" render-epic-ledger --input "$ledger_root_checkpoint_fixture")"
run_test "ledger_root_checkpoints_scoped_by_item" "yes" "$(grep -Fq 'Checkpoints: #920 plan/technical=pending' <<< "$root_checkpoint_ledger_output" && ! grep '#918' <<< "$(grep 'Item A' <<< "$root_checkpoint_ledger_output")" && echo yes || echo no)"
ledger_update_output="$(MOCK_COMMENT_MODE=existing "$HELPER" apply-epic-ledger --input "$ledger_fixture" --epic 900)"
run_test "updates_existing_epic_ledger_comment" "UPDATED_COMMENT_ID=456" "$ledger_update_output"

run_test "uses_json_input_for_comments" "yes" "$(grep -q -- '--input -' "$CALL_LOG" && echo yes || echo no)"

bypass_output="$("$HELPER" render-reviewer-access-bypass --input "$bypass_fixture")"
run_test "renders_reviewer_access_bypass_marker" "yes" "$(grep -q '<!-- reviewer-access-bypass -->' <<< "$bypass_output" && echo yes || echo no)"
run_test "renders_reviewer_access_bypass_state" "yes" "$(grep -q 'authorized_pending_attempt' <<< "$bypass_output" && echo yes || echo no)"
run_test "renders_reviewer_access_bypass_action" "yes" "$(grep -q 'gh pr merge 42 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' <<< "$bypass_output" && echo yes || echo no)"
run_test "redacts_bypass_tokens_and_paths" "yes" "$(
  grep -q '\[REDACTED_TOKEN\]' <<< "$bypass_output" &&
    grep -q '\[REDACTED_LOCAL_PATH\]' <<< "$bypass_output" &&
    echo yes || echo no
)"

bypass_create_output="$("$HELPER" apply-reviewer-access-bypass --input "$bypass_fixture" --pr 42)"
run_test "creates_reviewer_access_bypass_when_missing" "CREATED_COMMENT=1" "$bypass_create_output"
bypass_update_output="$(MOCK_COMMENT_MODE=existing-bypass "$HELPER" apply-reviewer-access-bypass --input "$bypass_fixture" --pr 42)"
run_test "updates_existing_reviewer_access_bypass" "UPDATED_COMMENT_ID=789" "$bypass_update_output"

# --- per-finding advisory warnings ---

# Fixture: advisory_count=2 but only 1 advisories[] entry (under-reported)
sparse_advisory_fixture="$TMP_ROOT/sparse-advisory.json"
jq '.reviewer.advisory_count = 2 | .advisories = [.advisories[0]]' "$pr_fixture" > "$sparse_advisory_fixture"

# Fixture: advisory_count=2 with bulk-acceptance rationale pattern
bulk_accepted_fixture="$TMP_ROOT/bulk-accepted.json"
jq '.reviewer.advisory_count = 2 | .advisories[0].rationale = "reviewed and accepted all advisories"' "$pr_fixture" > "$bulk_accepted_fixture"

# Fixture: advisory_count=0 with no advisories — should produce no warnings
no_advisory_fixture="$TMP_ROOT/no-advisory.json"
jq '.reviewer.advisory_count = 0 | .advisories = []' "$pr_fixture" > "$no_advisory_fixture"

sparse_stderr="$("$HELPER" render-pr-disposition --input "$sparse_advisory_fixture" 2>&1 >/dev/null)"
run_test "warns_when_advisory_entries_less_than_count" "yes" \
  "$(grep -q 'protocol requires one entry per finding' <<< "$sparse_stderr" && echo yes || echo no)"

bulk_stderr="$("$HELPER" render-pr-disposition --input "$bulk_accepted_fixture" 2>&1 >/dev/null)"
run_test "warns_on_bulk_acceptance_rationale" "yes" \
  "$(grep -q 'generic bulk-acceptance rationale' <<< "$bulk_stderr" && echo yes || echo no)"

no_advisory_stderr="$("$HELPER" render-pr-disposition --input "$no_advisory_fixture" 2>&1 >/dev/null)"
run_test "no_warn_when_advisory_count_zero" "yes" \
  "$(printf '%s' "$no_advisory_stderr" | wc -c | tr -d ' ' | grep -qx '0' && echo yes || echo no)"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
