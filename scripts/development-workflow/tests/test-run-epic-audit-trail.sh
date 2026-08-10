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
  "why_safe_to_merge": {
    "scope": "audit trail rendering only, no schema migration",
    "tests": "unit tests in test-run-epic-audit-trail.sh, all green",
    "reviewer_outcome": "clean, 0 blocking",
    "ci_outcome": "green on abc123",
    "rollback_or_cleanup_risk": "low - additive rendering change only"
  },
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
  }
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
wrong_typed_item_fixture="$TMP_ROOT/wrong-typed-item.json"
jq '.item = "a-string"' "$pr_fixture" > "$wrong_typed_item_fixture"
wrong_typed_ledger_epic_fixture="$TMP_ROOT/wrong-typed-ledger-epic.json"
jq '.epic = "a-string"' "$ledger_fixture" > "$wrong_typed_ledger_epic_fixture"
# CodeRabbit finding on PR #1459: a wrong-typed *optional* section
# (invocation_policy / checkpoint_policy / verification — none of which
# are part of the required-field guard above) crashed jq mid-render, deep
# inside the `{ ... } | redact_text` body pipe. That failure could not
# reach the caller via the top-level `missing` guard at all, and — because
# the `{ ... }` block runs in its own subshell as a non-last pipeline
# stage — a shared flag variable set inside it is invisible once the pipe
# returns, so even a deferred-check fix would silently mask the failure a
# second way. wrong_typed_invocation_policy_fixture is present (not null)
# but the wrong JSON type, which is the reproduction shape.
wrong_typed_invocation_policy_fixture="$TMP_ROOT/wrong-typed-invocation-policy.json"
jq '.invocation_policy = "a-string"' "$pr_fixture" > "$wrong_typed_invocation_policy_fixture"
wrong_typed_checkpoint_policy_fixture="$TMP_ROOT/wrong-typed-checkpoint-policy.json"
jq '.checkpoint_policy = "a-string"' "$pr_fixture" > "$wrong_typed_checkpoint_policy_fixture"
wrong_typed_verification_fixture="$TMP_ROOT/wrong-typed-verification.json"
jq '.verification = "a-string"' "$pr_fixture" > "$wrong_typed_verification_fixture"
# Same defect class, found during review of this PR's fix: .protocol_deviations
# is an optional array field with no upstream validator (unlike .advisories,
# which is protected by validate_advisories before render_pr_disposition is
# ever called). A wrong-typed value crashed jq mid-render the same way the
# CodeRabbit-flagged sections did.
wrong_typed_protocol_deviations_fixture="$TMP_ROOT/wrong-typed-protocol-deviations.json"
jq '.protocol_deviations = "a-string"' "$pr_fixture" > "$wrong_typed_protocol_deviations_fixture"
# Issue #1436: .why_safe_to_merge is required by run-epic-risk-classifier.sh's
# why_safe_complete() for medium-risk PRs but, before this fix, was never
# rendered by render_pr_disposition() — a jq-based renderer silently drops
# unconsumed top-level keys instead of warning. missing_why_safe_to_merge_fixture
# and wrong_typed_why_safe_to_merge_fixture exercise both failure directions of
# the fix: the "Not recorded." fallback when absent, and the same
# error_exit-on-jq-failure guard shape used by the other optional sections
# above when the value is present but the wrong JSON type.
missing_why_safe_to_merge_fixture="$TMP_ROOT/missing-why-safe-to-merge.json"
jq 'del(.why_safe_to_merge)' "$pr_fixture" > "$missing_why_safe_to_merge_fixture"
wrong_typed_why_safe_to_merge_fixture="$TMP_ROOT/wrong-typed-why-safe-to-merge.json"
jq '.why_safe_to_merge = "a-string"' "$pr_fixture" > "$wrong_typed_why_safe_to_merge_fixture"
# CodeRabbit finding on this PR: jq's `//` operator treats `false` as falsy,
# so `.why_safe_to_merge // null` previously evaluated a boolean `false` value
# the same as an absent field — silently falling back to "Not recorded."
# instead of rejecting the wrong type, letting apply mode write an audit
# comment for invalid evidence. boolean_why_safe_to_merge_fixture exercises
# that specific falsy-boolean edge case.
boolean_why_safe_to_merge_fixture="$TMP_ROOT/boolean-why-safe-to-merge.json"
jq '.why_safe_to_merge = false' "$pr_fixture" > "$boolean_why_safe_to_merge_fixture"
# Same issue's complementary ask: a strict-unknown-keys warning so a future
# unconsumed top-level key degrades loudly (a warning, not silent data loss)
# instead of repeating this exact defect.
unknown_key_fixture="$TMP_ROOT/unknown-key.json"
jq '.mystery_field = "surprise"' "$pr_fixture" > "$unknown_key_fixture"

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
wrong_typed_bypass_fixture="$TMP_ROOT/wrong-typed-bypass.json"
jq '.authorization = "a-string"' "$bypass_fixture" > "$wrong_typed_bypass_fixture"
mismatched_bypass_pr_fixture="$TMP_ROOT/mismatched-bypass-pr.json"
jq '.pr.number = 99' "$bypass_fixture" > "$mismatched_bypass_pr_fixture"
mismatched_bypass_action_fixture="$TMP_ROOT/mismatched-bypass-action.json"
jq '.proposed_action = "gh pr merge 99 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$bypass_fixture" > "$mismatched_bypass_action_fixture"
mismatched_bypass_head_fixture="$TMP_ROOT/mismatched-bypass-head.json"
jq '.proposed_action = "gh pr merge 42 --admin --match-head-commit bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "$bypass_fixture" > "$mismatched_bypass_head_fixture"
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
run_fails_contains "rejects_mismatched_bypass_head_on_apply" "proposed action 'gh pr merge 42 --admin --match-head-commit <head-sha>'" "$HELPER" apply-reviewer-access-bypass --input "$mismatched_bypass_head_fixture" --pr 42
run_fails_contains "rejects_missing_input_file" "input file not found" "$HELPER" render-pr-disposition --input "$missing_fixture"
run_fails_contains "rejects_empty_input_file" "input file is empty" "$HELPER" render-pr-disposition --input "$empty_fixture"
run_fails_contains "rejects_malformed_input_json" "input file is not valid JSON" "$HELPER" render-pr-disposition --input "$malformed_fixture"

pr_output="$("$HELPER" render-pr-disposition --input "$pr_fixture")"
run_test "renders_pr_marker" "yes" "$(grep -q '<!-- run-epic:pr-disposition -->' <<< "$pr_output" && echo yes || echo no)"
run_test "renders_reviewed_sha" "yes" "$(grep -q 'abc123' <<< "$pr_output" && echo yes || echo no)"
run_test "renders_advisory_decision" "yes" "$(grep -q 'accepted' <<< "$pr_output" && echo yes || echo no)"
run_test "renders_protocol_deviation" "yes" "$(grep -q 'documented<br>rationale' <<< "$pr_output" && echo yes || echo no)"
# Issue #1436: assert on the actual rendered content of every why_safe_to_merge
# field, not just section presence — a header with no field content would
# still be silent data loss for the evidence a medium-risk merge relies on.
run_test "renders_why_safe_to_merge_section" "yes" "$(
  grep -q '### Why Safe to Merge' <<< "$pr_output" &&
    grep -Fq -- '- Scope: audit trail rendering only, no schema migration' <<< "$pr_output" &&
    grep -Fq -- '- Tests: unit tests in test-run-epic-audit-trail.sh, all green' <<< "$pr_output" &&
    grep -Fq -- '- Reviewer outcome: clean, 0 blocking' <<< "$pr_output" &&
    grep -Fq -- '- CI outcome: green on abc123' <<< "$pr_output" &&
    grep -Fq -- '- Rollback or cleanup risk: low - additive rendering change only' <<< "$pr_output" &&
    echo yes || echo no
)"
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

missing_why_output="$("$HELPER" render-pr-disposition --input "$missing_why_safe_to_merge_fixture")"
run_test "why_safe_to_merge_optional_when_absent" "yes" "$(
  awk '/### Why Safe to Merge/,/### Invocation Policy/' <<< "$missing_why_output" | grep -q 'Not recorded.' && echo yes || echo no
)"

unknown_key_stderr="$("$HELPER" render-pr-disposition --input "$unknown_key_fixture" 2>&1 >/dev/null)"
run_test "warns_on_unrecognized_top_level_key" "yes" "$(
  grep -q 'unrecognized top-level PR disposition field(s)' <<< "$unknown_key_stderr" &&
    grep -q 'mystery_field' <<< "$unknown_key_stderr" &&
    echo yes || echo no
)"

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
echo "=== Planted-violation regression: apply-* required-field guard must not be inert (#1430) ==="
# Prior to the fix, a wrong-typed field (e.g. .item being a string instead of
# an object) made the required-field jq computation crash silently inside a
# command-substituted context (`body="$(render_pr_disposition ...)"`), which
# `set -e` does not abort. The guard's own [ -n "$missing" ] check then read
# an empty string (jq produced no stdout) and passed vacuously, so apply-*
# posted an incomplete audit comment and exited 0. render_pr_disposition() and
# render_reviewer_access_bypass() had this defect and were fixed with
# try/catch + explicit jq-exit-status capture (see the comments in
# run-epic-audit-trail.sh). render_epic_ledger() uses a different guard shape
# (`jq -e ... ; if ! ...` — the jq exit status is already control-flow-tested,
# so a crash correctly triggers `error_exit` even before this fix); it was
# audited and left unchanged, and its wrong_typed_epic case below is a
# confirmatory coverage test, not a regression case for this PR. These tests
# plant the violation against all three apply-* subcommands and assert each
# now fails loudly with no partial gh write, while a complete input still
# succeeds (already proven above by the creates_*/updates_* tests).

calls_before="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_fails_contains "apply_pr_disposition_rejects_wrong_typed_item" \
  "missing required PR disposition fields: item.number, item.title" \
  "$HELPER" apply-pr-disposition --input "$wrong_typed_item_fixture" --pr 10
calls_after="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_test "apply_pr_disposition_wrong_type_writes_no_comment" "$calls_before" "$calls_after"

calls_before="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_fails_contains "apply_epic_ledger_rejects_wrong_typed_epic" \
  "missing required epic ledger fields" \
  "$HELPER" apply-epic-ledger --input "$wrong_typed_ledger_epic_fixture" --epic 900
calls_after="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_test "apply_epic_ledger_wrong_type_writes_no_comment" "$calls_before" "$calls_after"

calls_before="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_fails_contains "apply_reviewer_access_bypass_rejects_wrong_typed_authorization" \
  "missing required reviewer access-bypass fields: authorization.authorized_by, authorization.authorized_at, authorization.authorization_text" \
  "$HELPER" apply-reviewer-access-bypass --input "$wrong_typed_bypass_fixture" --pr 42
calls_after="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_test "apply_reviewer_access_bypass_wrong_type_writes_no_comment" "$calls_before" "$calls_after"

# Same defect, exercised via the direct render-* path too: a wrong-typed
# field must be reported precisely as missing rather than crashing jq.
run_fails_contains "render_pr_disposition_rejects_wrong_typed_item" \
  "missing required PR disposition fields: item.number, item.title" \
  "$HELPER" render-pr-disposition --input "$wrong_typed_item_fixture"
run_fails_contains "render_reviewer_access_bypass_rejects_wrong_typed_authorization" \
  "missing required reviewer access-bypass fields: authorization.authorized_by, authorization.authorized_at, authorization.authorization_text" \
  "$HELPER" render-reviewer-access-bypass --input "$wrong_typed_bypass_fixture"

echo ""
echo "=== Planted-violation regression: wrong-typed optional section must not silently degrade (CodeRabbit finding, #1430) ==="
# A second, deeper layer of the same defect class (found by CodeRabbit
# reviewing this PR): invocation_policy, checkpoint_policy, and
# verification are *optional* fields, not covered by the required-field
# `missing` guard above. A wrong-typed value for any of them (present, not
# null/absent) crashed jq mid-render inside the `{ ... } | redact_text`
# body pipe. In apply mode this was worse than the top-level guard bug:
# execution continued past the crash to the end of the block (still inside
# the -e-ignored substitution context), so the function returned exit 0
# with a body that silently dropped just that one section, and
# apply-pr-disposition posted it. Each of the five risky jq captures in
# render_pr_disposition now calls error_exit immediately on failure rather
# than deferring to a flag (a shared flag set inside `{ ... }` would not
# survive the pipe: `{ ... } | redact_text` runs the `{ ... }` stage in its
# own subshell as a non-last pipeline stage).

calls_before="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_fails_contains "apply_pr_disposition_rejects_wrong_typed_invocation_policy" \
  "failed to render invocation policy detail" \
  "$HELPER" apply-pr-disposition --input "$wrong_typed_invocation_policy_fixture" --pr 10
calls_after="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_test "apply_pr_disposition_wrong_typed_invocation_policy_writes_no_comment" "$calls_before" "$calls_after"

calls_before="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_fails_contains "apply_pr_disposition_rejects_wrong_typed_checkpoint_policy" \
  "failed to render checkpoint policy detail" \
  "$HELPER" apply-pr-disposition --input "$wrong_typed_checkpoint_policy_fixture" --pr 10
calls_after="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_test "apply_pr_disposition_wrong_typed_checkpoint_policy_writes_no_comment" "$calls_before" "$calls_after"

calls_before="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_fails_contains "apply_pr_disposition_rejects_wrong_typed_verification" \
  "failed to render verification evidence" \
  "$HELPER" apply-pr-disposition --input "$wrong_typed_verification_fixture" --pr 10
calls_after="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_test "apply_pr_disposition_wrong_typed_verification_writes_no_comment" "$calls_before" "$calls_after"

# Same three cases via the direct render-* path.
run_fails_contains "render_pr_disposition_rejects_wrong_typed_invocation_policy" \
  "failed to render invocation policy detail" \
  "$HELPER" render-pr-disposition --input "$wrong_typed_invocation_policy_fixture"
run_fails_contains "render_pr_disposition_rejects_wrong_typed_checkpoint_policy" \
  "failed to render checkpoint policy detail" \
  "$HELPER" render-pr-disposition --input "$wrong_typed_checkpoint_policy_fixture"
run_fails_contains "render_pr_disposition_rejects_wrong_typed_verification" \
  "failed to render verification evidence" \
  "$HELPER" render-pr-disposition --input "$wrong_typed_verification_fixture"

echo ""
echo "=== Planted-violation regression: wrong-typed protocol_deviations must not silently degrade (found in review of PR #1459) ==="
# .protocol_deviations has no upstream validator (unlike .advisories, which
# validate_advisories protects before render_pr_disposition is ever called),
# so its jq capture inside the { ... } | redact_text body pipe needed the
# same point-of-failure error_exit guard applied to invocation_policy,
# checkpoint_policy, and verification above.

calls_before="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_fails_contains "apply_pr_disposition_rejects_wrong_typed_protocol_deviations" \
  "failed to render protocol deviations" \
  "$HELPER" apply-pr-disposition --input "$wrong_typed_protocol_deviations_fixture" --pr 10
calls_after="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_test "apply_pr_disposition_wrong_typed_protocol_deviations_writes_no_comment" "$calls_before" "$calls_after"

run_fails_contains "render_pr_disposition_rejects_wrong_typed_protocol_deviations" \
  "failed to render protocol deviations" \
  "$HELPER" render-pr-disposition --input "$wrong_typed_protocol_deviations_fixture"

# .advisories confirmatory coverage: validate_advisories already crashes
# loudly on a wrong-typed .advisories value before render_pr_disposition is
# reached, in both call contexts. This is not a fix in this PR — confirmatory
# only, kept alongside the protocol_deviations regression above so future
# changes to validate_advisories don't silently reopen the same defect class.
wrong_typed_advisories_fixture="$TMP_ROOT/wrong-typed-advisories.json"
jq '.advisories = "a-string"' "$pr_fixture" > "$wrong_typed_advisories_fixture"

calls_before="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_fails_contains "apply_pr_disposition_rejects_wrong_typed_advisories" \
  "failed to validate advisory entries" \
  "$HELPER" apply-pr-disposition --input "$wrong_typed_advisories_fixture" --pr 10
calls_after="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_test "apply_pr_disposition_wrong_typed_advisories_writes_no_comment" "$calls_before" "$calls_after"

run_fails_contains "render_pr_disposition_rejects_wrong_typed_advisories" \
  "failed to validate advisory entries" \
  "$HELPER" render-pr-disposition --input "$wrong_typed_advisories_fixture"

echo ""
echo "=== Planted-violation regression: why_safe_to_merge must render and must not silently degrade (issue #1436) ==="
# Before this fix, render_pr_disposition() never referenced .why_safe_to_merge
# anywhere in its jq programs, so the medium-risk merge evidence
# run-epic-risk-classifier.sh's why_safe_complete() requires was silently
# dropped from the durable audit comment with no error or warning. The
# rendering assertion above (renders_why_safe_to_merge_section) proves the
# positive direction with a complete block. This section proves the negative
# direction: a wrong-typed .why_safe_to_merge value (present, not
# null/absent) is caught by the same error_exit-on-jq-failure guard shape
# used for invocation_policy/checkpoint_policy/verification/protocol_deviations
# above, rather than crashing mid-render and silently posting a partial
# comment.

calls_before="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_fails_contains "apply_pr_disposition_rejects_wrong_typed_why_safe_to_merge" \
  "failed to render why-safe-to-merge detail" \
  "$HELPER" apply-pr-disposition --input "$wrong_typed_why_safe_to_merge_fixture" --pr 10
calls_after="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_test "apply_pr_disposition_wrong_typed_why_safe_to_merge_writes_no_comment" "$calls_before" "$calls_after"

run_fails_contains "render_pr_disposition_rejects_wrong_typed_why_safe_to_merge" \
  "failed to render why-safe-to-merge detail" \
  "$HELPER" render-pr-disposition --input "$wrong_typed_why_safe_to_merge_fixture"

# CodeRabbit finding on this PR: `false // null` evaluates to `null` in jq, so
# a boolean `false` value for .why_safe_to_merge was previously treated as
# absent (falling back to "Not recorded.") instead of being rejected as the
# wrong type — letting apply mode write an audit comment for invalid
# evidence. The fix replaced the `//`-based presence check with an explicit
# `== null` check plus an explicit `type != "object"` rejection.
calls_before="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_fails_contains "apply_pr_disposition_rejects_boolean_why_safe_to_merge" \
  "failed to render why-safe-to-merge detail" \
  "$HELPER" apply-pr-disposition --input "$boolean_why_safe_to_merge_fixture" --pr 10
calls_after="$(wc -l < "$CALL_LOG" | tr -d ' ')"
run_test "apply_pr_disposition_boolean_why_safe_to_merge_writes_no_comment" "$calls_before" "$calls_after"

run_fails_contains "render_pr_disposition_rejects_boolean_why_safe_to_merge" \
  "failed to render why-safe-to-merge detail" \
  "$HELPER" render-pr-disposition --input "$boolean_why_safe_to_merge_fixture"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
