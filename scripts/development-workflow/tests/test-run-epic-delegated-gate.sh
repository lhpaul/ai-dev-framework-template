#!/usr/bin/env bash
# test-run-epic-delegated-gate.sh - Unit tests for delegated /run-epic final gate.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
GATE="$REPO_ROOT/scripts/development-workflow/run-epic-delegated-gate.sh"

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
  issue\ edit*|pr\ create*|pr\ merge*|pr\ edit*|pr\ comment*|project\ item-edit*|project\ item-add*)
    printf 'mutating gh command was called: gh %s\n' "$*" >&2
    exit 99
    ;;
  *'mutation'*)
    printf 'mutating GraphQL operation was called: gh %s\n' "$*" >&2
    exit 99
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
  local name="$1"
  local expected="$2"
  local actual="$3"
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

write_fixture() {
  local name="$1"
  local filter="${2:-.}"
  local path="$TMP_ROOT/${name}.json"
  jq "$filter" "$base_fixture" > "$path"
  printf '%s\n' "$path"
}

decision_for() {
  "$GATE" --input "$1" --json | jq -r '.decision'
}

decision_with_policy_for() {
  "$GATE" --input "$1" --policy "$2" --json | jq -r '.decision'
}

reason_match_for() {
  local fixture="$1" pattern="$2"
  "$GATE" --input "$fixture" --json |
    jq -r --arg pattern "$pattern" 'any(.reasons[]?; test($pattern))'
}

base_fixture="$TMP_ROOT/base.json"
cat > "$base_fixture" <<'JSON'
{
  "policy": {
    "delegateReview": true,
    "mayMerge": true,
    "mayStartBacklog": true,
    "maxRisk": "medium"
  },
  "scope": {
    "source": "epic",
    "itemNumbers": [918]
  },
  "item": {
    "number": 918,
    "status": "In Development",
    "group": "eligible"
  },
  "pr": {
    "number": 42,
    "headRefName": "feature/918-delegated-review-merge-loop",
    "baseRefName": "develop-delegated-epic-orchestration",
    "isDraft": false,
    "mergeStateStatus": "CLEAN",
    "labels": ["ready-for-human-review", "ready-for-regression"],
    "inScope": true,
    "unresolvedBlockingThreads": 0,
    "auditDispositionPresent": true
  },
  "reviewer": {
    "status": "clean",
    "blockingCount": 0,
    "advisoryCount": 1,
    "acceptedAdvisoriesWithoutRationale": 0
  },
  "risk": {
    "risk": "medium",
    "mergePermitted": true,
    "blockers": []
  },
  "statusChecks": [
    {"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"},
    {"name": "Reviewer-loop completion guard (#42)", "state": "SUCCESS", "conclusion": "SUCCESS"}
  ]
}
JSON

missing_file="$TMP_ROOT/missing.json"
empty_file="$TMP_ROOT/empty.json"
: > "$empty_file"
malformed_file="$TMP_ROOT/malformed.json"
printf '{"oops"\n' > "$malformed_file"
whitespace_file="$TMP_ROOT/whitespace.json"
printf ' \n\t\n' > "$whitespace_file"

echo ""
echo "=== Run epic delegated gate ==="

run_fails_contains "requires_input" "--input is required" "$GATE"
run_fails_contains "rejects_pr_mode" "Unknown option: --pr" "$GATE" --pr 42
run_fails_contains "rejects_missing_fixture" "input file not found" "$GATE" --input "$missing_file"
run_fails_contains "rejects_empty_fixture" "input file is empty" "$GATE" --input "$empty_file"
run_fails_contains "rejects_malformed_fixture" "input file is not valid JSON" "$GATE" --input "$malformed_file"
run_fails_contains "rejects_whitespace_fixture" "input file is not valid JSON" "$GATE" --input "$whitespace_file"

no_ci_fixture="$(write_fixture no-ci '.statusChecks = [] | .ciPolicy = "none"')"
run_test "ci_policy_none_allows_empty_checks" "merge_allowed" "$(decision_for "$no_ci_fixture")"

no_ci_failed_fixture="$(write_fixture no-ci-failed '.statusChecks = [{"name": "guard", "status": "COMPLETED", "conclusion": "FAILURE"}] | .ciPolicy = "none"')"
run_test "ci_policy_none_skips_failed_checks" "merge_allowed" "$(decision_for "$no_ci_failed_fixture")"

stale_ci_risk_fixture="$(write_fixture stale-ci-risk '.statusChecks = [] | .ciPolicy = "none" | .risk = {mergePermitted: false, blockers: ["required CI state is missing or unavailable"]}')"
run_test "ci_policy_none_ignores_stale_ci_risk_snapshot" "merge_allowed" "$(decision_for "$stale_ci_risk_fixture")"

hub_ci_dir="$TMP_ROOT/hub-ci-policy-none"
mkdir -p "$hub_ci_dir"
cat > "$hub_ci_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      ci_policy: none
YAML

wrong_slug_hub_fixture="$(write_fixture wrong-slug-hub '.statusChecks = [] | .github_repo = "example/wrong-app"')"
run_test "hub_ci_policy_skips_unknown_github_slug" "blocked" "$("$GATE" --input "$wrong_slug_hub_fixture" --repo-root "$hub_ci_dir" --json | jq -r '.decision')"

missing_ci_hub_fixture="$(write_fixture missing-ci-hub '.statusChecks = [] | .productRepo = {name: "mobile-app"}')"
run_test "hub_ci_policy_none_from_resolver" "merge_allowed" "$("$GATE" --input "$missing_ci_hub_fixture" --repo-root "$hub_ci_dir" --product-repo mobile-app --json | jq -r '.decision')"

stale_slug_hub_fixture="$(write_fixture stale-slug-hub '.statusChecks = [] | .productRepo = {name: "mobile-app"} | .github_repo = "example/stale-slug"')"
run_test "hub_ci_policy_uses_product_repo_name_over_stale_slug" "merge_allowed" "$("$GATE" --input "$stale_slug_hub_fixture" --repo-root "$hub_ci_dir" --product-repo mobile-app --json | jq -r '.decision')"

clean_fixture="$(write_fixture clean)"
run_test "merge_allowed_when_all_gates_clean" "merge_allowed" "$(decision_for "$clean_fixture")"
run_test "merge_permitted_true" "true" "$("$GATE" --input "$clean_fixture" --json | jq -r '.mergePermitted')"

no_review_fixture="$(write_fixture no-review '.policy.delegateReview = false')"
run_test "missing_delegate_review_requires_human" "human_required" "$(decision_for "$no_review_fixture")"
run_test "missing_delegate_review_reason" "true" "$(reason_match_for "$no_review_fixture" "delegated review")"

null_policy_fixture="$(write_fixture null-policy '.policy = null')"
run_test "null_policy_requires_human" "human_required" "$(decision_for "$null_policy_fixture")"

string_policy_fixture="$(write_fixture string-policy '.policy = "delegate"')"
run_test "non_object_policy_requires_human" "human_required" "$(decision_for "$string_policy_fixture")"

no_merge_fixture="$(write_fixture no-merge '.policy.mayMerge = false')"
run_test "missing_merge_authority_requires_human" "human_required" "$(decision_for "$no_merge_fixture")"

policy_override_file="$TMP_ROOT/policy-override.json"
jq '.policy' "$base_fixture" > "$policy_override_file"
run_test "policy_file_overrides_input_policy" "merge_allowed" "$(decision_with_policy_for "$no_merge_fixture" "$policy_override_file")"

backlog_denied_fixture="$(write_fixture backlog-denied '.item.status = "Backlog" | .policy.mayStartBacklog = false')"
run_test "backlog_policy_denied_requires_human" "human_required" "$(decision_for "$backlog_denied_fixture")"

out_of_scope_fixture="$(write_fixture out-of-scope '.pr.inScope = false')"
run_test "candidate_not_in_scope_requires_human" "human_required" "$(decision_for "$out_of_scope_fixture")"

draft_fixture="$(write_fixture draft '.pr.isDraft = true')"
run_test "draft_blocks" "blocked" "$(decision_for "$draft_fixture")"

missing_human_label_fixture="$(write_fixture no-human-label '.pr.labels = ["ready-for-regression"]')"
run_test "requires_human_review_label" "blocked" "$(decision_for "$missing_human_label_fixture")"

missing_regression_fixture="$(write_fixture no-regression '.pr.labels = ["ready-for-human-review"]')"
run_test "feature_pr_requires_regression_label" "blocked" "$(decision_for "$missing_regression_fixture")"

spec_without_regression_fixture="$(write_fixture spec-no-regression '.pr.headRefName = "spec/918-delegated-review-merge-loop" | .pr.labels = ["ready-for-human-review"]')"
run_test "spec_pr_skips_regression_label" "merge_allowed" "$(decision_for "$spec_without_regression_fixture")"

implementation_plan_skipped_fixture="$(write_fixture implementation-plan-skipped '.pr.headRefName = "implementation-plan/918-delegated-review-merge-loop" | .pr.labels = ["ready-for-human-review"] | .statusChecks += [{"name": "E2E regression (placeholder)", "status": "COMPLETED", "conclusion": "SKIPPED"}]')"
run_test "implementation_plan_pr_allows_skipped_regression_check" "merge_allowed" "$(decision_for "$implementation_plan_skipped_fixture")"

spec_neutral_fixture="$(write_fixture spec-neutral '.pr.headRefName = "spec/918-delegated-review-merge-loop" | .pr.labels = ["ready-for-human-review"] | .statusChecks += [{"name": "E2E regression (placeholder)", "status": "COMPLETED", "conclusion": "NEUTRAL"}]')"
run_test "spec_pr_allows_neutral_regression_check" "merge_allowed" "$(decision_for "$spec_neutral_fixture")"

implementation_skipped_missing_label_fixture="$(write_fixture implementation-skipped-missing-label '.pr.labels = ["ready-for-human-review"] | .statusChecks += [{"name": "E2E regression (placeholder)", "status": "COMPLETED", "conclusion": "SKIPPED"}]')"
run_test "implementation_pr_still_requires_regression_label" "blocked" "$(decision_for "$implementation_skipped_missing_label_fixture")"

implementation_skipped_with_label_fixture="$(write_fixture implementation-skipped-with-label '.statusChecks += [{"name": "E2E regression (placeholder)", "status": "COMPLETED", "conclusion": "SKIPPED"}]')"
run_test "implementation_pr_with_regression_label_allows_skipped_check" "merge_allowed" "$(decision_for "$implementation_skipped_with_label_fixture")"

graduation_fixture="$(write_fixture graduation '.pr.headRefName = "develop-graduation-guard" | .pr.baseRefName = "develop" | .pr.labels = ["ready-for-human-review"]')"
run_test "graduation_pr_requires_explicit_approval" "human_required" "$(decision_for "$graduation_fixture")"
run_test "graduation_pr_reason_names_guard" "true" "$(reason_match_for "$graduation_fixture" "graduation_approval_required")"

missing_graduation_policy_fixture="$(write_fixture missing-graduation-policy '.pr.headRefName = "develop-graduation-guard" | .pr.baseRefName = "develop" | .pr.labels = ["ready-for-human-review"] | del(.policy.graduationApproved)')"
run_test "missing_graduation_approval_defaults_unapproved" "human_required" "$(decision_for "$missing_graduation_policy_fixture")"

develop_prefixed_path_fixture="$(write_fixture develop-prefixed-path '.pr.headRefName = "develop/graduation-guard" | .pr.baseRefName = "develop" | .pr.labels = ["ready-for-human-review"]')"
run_test "develop_prefixed_path_branch_is_not_graduation" "merge_allowed" "$(decision_for "$develop_prefixed_path_fixture")"

develop_branch_to_integration_fixture="$(write_fixture develop-branch-to-integration '.pr.headRefName = "develop-graduation-guard" | .pr.baseRefName = "develop-parent" | .pr.labels = ["ready-for-human-review"]')"
run_test "develop_branch_to_non_develop_base_is_not_graduation" "merge_allowed" "$(decision_for "$develop_branch_to_integration_fixture")"

approved_graduation_fixture="$(write_fixture approved-graduation '.pr.headRefName = "develop-graduation-guard" | .pr.baseRefName = "develop" | .pr.labels = ["ready-for-human-review"] | .policy.graduationApproved = true')"
run_test "graduation_pr_allows_recorded_approval" "merge_allowed" "$(decision_for "$approved_graduation_fixture")"

setup_fixture="$(write_fixture setup '.pr.labels += ["needs-setup"]')"
run_test "needs_setup_requires_human" "human_required" "$(decision_for "$setup_fixture")"

ci_failure_fixture="$(write_fixture ci-failure '.statusChecks[0].conclusion = "FAILURE"')"
run_test "ci_failure_requires_fix" "fix_required" "$(decision_for "$ci_failure_fixture")"

ci_in_progress_fixture="$(write_fixture ci-in-progress '.statusChecks[0].status = "IN_PROGRESS" | .statusChecks[0].conclusion = "SUCCESS"')"
run_test "ci_in_progress_success_conclusion_requires_fix" "fix_required" "$(decision_for "$ci_in_progress_fixture")"

for terminal_conclusion in FAILURE CANCELLED TIMED_OUT ACTION_REQUIRED STARTUP_FAILURE ""; do
  fixture_suffix="${terminal_conclusion:-missing}"
  terminal_fixture="$(write_fixture "terminal-${fixture_suffix}" ".statusChecks = [{\"name\": \"guard\", \"status\": \"COMPLETED\", \"conclusion\": \"${terminal_conclusion}\"}]")"
  run_test "completed_${fixture_suffix}_check_requires_fix" "fix_required" "$(decision_for "$terminal_fixture")"
done

for pending_state in IN_PROGRESS QUEUED PENDING EXPECTED; do
  pending_fixture="$(write_fixture "pending-${pending_state}" ".statusChecks = [{\"name\": \"guard\", \"status\": \"${pending_state}\", \"conclusion\": \"SUCCESS\"}]")"
  run_test "${pending_state}_check_requires_fix" "fix_required" "$(decision_for "$pending_fixture")"
done

status_context_fixture="$(write_fixture status-context '.statusChecks = [{"name": "legacy", "state": "SUCCESS", "conclusion": "SUCCESS"}]')"
run_test "status_context_success_is_terminal" "merge_allowed" "$(decision_for "$status_context_fixture")"

missing_ci_fixture="$(write_fixture missing-ci '.statusChecks = []')"
run_test "missing_ci_blocks" "blocked" "$(decision_for "$missing_ci_fixture")"

dirty_merge_fixture="$(write_fixture dirty-merge '.pr.mergeStateStatus = "DIRTY"')"
run_test "dirty_merge_blocks" "blocked" "$(decision_for "$dirty_merge_fixture")"

thread_fixture="$(write_fixture unresolved-thread '.pr.unresolvedBlockingThreads = 1')"
run_test "unresolved_thread_requires_fix" "fix_required" "$(decision_for "$thread_fixture")"

reviewer_fixture="$(write_fixture reviewer-blocker '.reviewer.blockingCount = 1')"
run_test "reviewer_blocker_requires_fix" "fix_required" "$(decision_for "$reviewer_fixture")"

advisory_fixture="$(write_fixture advisory-missing-rationale '.reviewer.acceptedAdvisoriesWithoutRationale = 1')"
run_test "advisory_without_rationale_requires_fix" "fix_required" "$(decision_for "$advisory_fixture")"

risk_fixture="$(write_fixture risk-blocked '.risk.mergePermitted = false | .risk.blockers = ["high exceeds medium"]')"
run_test "risk_gate_requires_human" "human_required" "$(decision_for "$risk_fixture")"

snake_risk_fixture="$(write_fixture snake-risk 'del(.risk.mergePermitted) | .risk.merge_permitted = true')"
run_test "risk_gate_accepts_classifier_shape" "merge_allowed" "$(decision_for "$snake_risk_fixture")"

missing_risk_fixture="$(write_fixture missing-risk 'del(.risk)')"
run_test "missing_risk_gate_requires_human" "human_required" "$(decision_for "$missing_risk_fixture")"

pending_checkpoint_fixture="$(write_fixture pending-checkpoint '.item.number = 1023 | .pr.headRefName = "feature/1023-human-checkpoint-gates" | .policy.checkpoints = [{"item_number":1023,"stage":"implementation","domain":"technical","reason":"sensitive merge gate behavior","required_human_action":"approve delegated gate checkpoint handling","satisfaction_state":"pending"}]')"
run_test "pending_checkpoint_requires_human" "human_required" "$(decision_for "$pending_checkpoint_fixture")"
run_test "pending_checkpoint_reason_names_action" "true" "$(reason_match_for "$pending_checkpoint_fixture" "approve delegated gate checkpoint handling")"

snake_case_checkpoint_fixture="$(write_fixture snake-case-checkpoint '.item.number = 1023 | .pr.headRefName = "feature/1023-human-checkpoint-gates" | .policy.effective_policy.checkpoints = [{"item_number":1023,"stage":"implementation","domain":"technical","reason":"snake case policy","required_human_action":"approve snake case checkpoint","satisfaction_state":"pending"}]')"
run_test "snake_case_policy_checkpoint_requires_human" "human_required" "$(decision_for "$snake_case_checkpoint_fixture")"

invocation_policy_checkpoint_fixture="$(write_fixture invocation-policy-checkpoint '.item.number = 1023 | .pr.headRefName = "feature/1023-human-checkpoint-gates" | .invocation_policy.effective_policy.checkpoints = [{"item_number":1023,"stage":"implementation","domain":"technical","reason":"invocation policy","required_human_action":"approve invocation checkpoint","satisfaction_state":"pending"}]')"
run_test "invocation_policy_checkpoint_requires_human" "human_required" "$(decision_for "$invocation_policy_checkpoint_fixture")"

satisfied_checkpoint_fixture="$(write_fixture satisfied-checkpoint '.item.number = 1023 | .pr.headRefName = "feature/1023-human-checkpoint-gates" | .policy.checkpoints = [{"item_number":1023,"stage":"implementation","domain":"technical","reason":"sensitive merge gate behavior","required_human_action":"approve delegated gate checkpoint handling","satisfaction_state":"satisfied","satisfied_by":"lhpaul"}]')"
run_test "satisfied_checkpoint_allows_merge" "merge_allowed" "$(decision_for "$satisfied_checkpoint_fixture")"

other_item_checkpoint_fixture="$(write_fixture other-item-checkpoint '.item.number = 1023 | .pr.headRefName = "feature/1023-human-checkpoint-gates" | .policy.checkpoints = [{"item_number":9999,"stage":"implementation","domain":"technical","reason":"other item","required_human_action":"ignore","satisfaction_state":"pending"}]')"
run_test "other_item_checkpoint_does_not_block" "merge_allowed" "$(decision_for "$other_item_checkpoint_fixture")"

future_stage_checkpoint_fixture="$(write_fixture future-stage-checkpoint '.item.number = 1023 | .pr.headRefName = "implementation-plan/1023-human-checkpoint-gates" | .policy.checkpoints = [{"item_number":1023,"stage":"implementation","domain":"technical","reason":"future implementation review","required_human_action":"approve implementation","satisfaction_state":"pending"}]')"
run_test "future_stage_checkpoint_does_not_block" "merge_allowed" "$(decision_for "$future_stage_checkpoint_fixture")"

stale_checkpoint_label_fixture="$(write_fixture stale-checkpoint-label '.pr.labels += ["human-checkpoint-required"]')"
run_test "stale_checkpoint_label_requires_human" "human_required" "$(decision_for "$stale_checkpoint_label_fixture")"

audit_fixture="$(write_fixture audit-missing '.pr.auditDispositionPresent = false')"
run_test "audit_required_before_merge" "blocked" "$(decision_for "$audit_fixture")"

reviewer_access_base_fixture="$(write_fixture reviewer-access-base '
  .repository = "example/mobile-app"
  | .pr.headSha = "abc123"
  | .pr.mergeStateStatus = "BLOCKED"
  | .reviewer.reason = "forbidden"
  | .reviewerChecks = [{"name":"Haystack / Review","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://example.test/haystack"}]
  | .accessRestriction = {
      provider: "haystack",
      reason: "forbidden",
      source: "reviewer-loop",
      evidence: "HTTP 403 from reviewer details URL",
      remediationAttempted: false,
      cannotUnblockInTime: false,
      bypassReason: ""
    }
')"
run_test "access_restricted_recommends_remediation_first" "human_required:access_restricted" "$(
  "$GATE" --input "$reviewer_access_base_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

authorization_required_fixture="$(write_fixture authorization-required '
  .repository = "example/mobile-app"
  | .pr.headSha = "abc123"
  | .pr.mergeStateStatus = "BLOCKED"
  | .reviewer.reason = "forbidden"
  | .reviewerChecks = [{"name":"Haystack / Review","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://example.test/haystack"}]
  | .accessRestriction = {
      provider: "haystack",
      reason: "forbidden",
      source: "reviewer-loop",
      evidence: "HTTP 403 from reviewer details URL",
      remediationAttempted: true,
      cannotUnblockInTime: true,
      bypassReason: "organization approval cannot complete before release window"
    }
')"
authorization_required_output="$("$GATE" --input "$authorization_required_fixture" --json)"
authorization_fingerprint="$(printf '%s\n' "$authorization_required_output" | jq -r '.reviewerAccess.evidenceFingerprint')"
run_test "reviewer_access_requires_named_authorization" "human_required:authorization_required" "$(printf '%s\n' "$authorization_required_output" | jq -r '.decision + ":" + .reviewerAccess.classification')"
run_test "reviewer_access_reports_fingerprint" "yes" "$(grep -Eq '^sha256:[0-9a-f]{64}$' <<< "$authorization_fingerprint" && echo yes || echo no)"

authorization_stale_fixture="$(write_fixture authorization-stale "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"abc123\"
  | .pr.mergeStateStatus = \"BLOCKED\"
  | .reviewer.reason = \"forbidden\"
  | .reviewerChecks = [{\"name\":\"Haystack / Review\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\",\"detailsUrl\":\"https://example.test/haystack\"}]
  | .accessRestriction = {
      provider: \"haystack\",
      reason: \"forbidden\",
      source: \"reviewer-loop\",
      evidence: \"HTTP 403 from reviewer details URL\",
      remediationAttempted: true,
      cannotUnblockInTime: true,
      bypassReason: \"organization approval cannot complete before release window\"
    }
  | .authorization = {
      pullRequest: 42,
      headSha: \"different-sha\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      authorizedBy: \"lhpaul\",
      authorizedAt: \"2026-07-29T12:00:00Z\",
      authorizationText: \"Approve admin merge for PR #42\"
    }
")"
run_test "reviewer_access_stale_authorization_blocks" "human_required:authorization_stale" "$(
  "$GATE" --input "$authorization_stale_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

audit_required_fixture="$(write_fixture access-audit-required "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"abc123\"
  | .pr.mergeStateStatus = \"BLOCKED\"
  | .reviewer.reason = \"forbidden\"
  | .reviewerChecks = [{\"name\":\"Haystack / Review\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\",\"detailsUrl\":\"https://example.test/haystack\"}]
  | .accessRestriction = {
      provider: \"haystack\",
      reason: \"forbidden\",
      source: \"reviewer-loop\",
      evidence: \"HTTP 403 from reviewer details URL\",
      remediationAttempted: true,
      cannotUnblockInTime: true,
      bypassReason: \"organization approval cannot complete before release window\"
    }
  | .authorization = {
      pullRequest: 42,
      headSha: \"abc123\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      authorizedBy: \"lhpaul\",
      authorizedAt: \"2026-07-29T12:00:00Z\",
      authorizationText: \"Approve admin merge for PR #42\"
    }
")"
run_test "reviewer_access_requires_pre_attempt_audit" "human_required:audit_required" "$(
  "$GATE" --input "$audit_required_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

exceptional_authorized_fixture="$(write_fixture access-exceptional-authorized "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"abc123\"
  | .pr.mergeStateStatus = \"BLOCKED\"
  | .reviewer.reason = \"forbidden\"
  | .reviewerChecks = [{\"name\":\"Haystack / Review\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\",\"detailsUrl\":\"https://example.test/haystack\"}]
  | .accessRestriction = {
      provider: \"haystack\",
      reason: \"forbidden\",
      source: \"reviewer-loop\",
      evidence: \"HTTP 403 from reviewer details URL\",
      remediationAttempted: true,
      cannotUnblockInTime: true,
      bypassReason: \"organization approval cannot complete before release window\"
    }
  | .authorization = {
      pullRequest: 42,
      headSha: \"abc123\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      authorizedBy: \"lhpaul\",
      authorizedAt: \"2026-07-29T12:00:00Z\",
      authorizationText: \"Approve admin merge for PR #42\"
    }
  | .bypassAudit = {
      present: true,
      state: \"authorized_pending_attempt\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      commentId: \"IC_kwDO\"
    }
")"
run_test "reviewer_access_exceptional_authorization_is_separate_result" "exceptional_bypass_authorized:false:true:gh pr merge 42 --admin" "$(
  "$GATE" --input "$exceptional_authorized_fixture" --json |
    jq -r '.decision + ":" + (.mergePermitted|tostring) + ":" + (.exceptionalAdminMergePermitted|tostring) + ":" + .reviewerAccess.proposedAction'
)"

exceptional_with_status_reviewer_fixture="$(write_fixture access-exceptional-status-reviewer "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"abc123\"
  | .pr.mergeStateStatus = \"BLOCKED\"
  | .statusChecks += [{\"name\":\"Haystack / Review\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\",\"detailsUrl\":\"https://example.test/haystack\"}]
  | .reviewer.reason = \"forbidden\"
  | .reviewerChecks = [{\"name\":\"Haystack / Review\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\",\"detailsUrl\":\"https://example.test/haystack\"}]
  | .accessRestriction = {
      provider: \"haystack\",
      reason: \"forbidden\",
      source: \"reviewer-loop\",
      evidence: \"HTTP 403 from reviewer details URL\",
      remediationAttempted: true,
      cannotUnblockInTime: true,
      bypassReason: \"organization approval cannot complete before release window\"
    }
")"
exceptional_status_reviewer_fingerprint="$("$GATE" --input "$exceptional_with_status_reviewer_fixture" --json | jq -r '.reviewerAccess.evidenceFingerprint')"
exceptional_with_status_reviewer_authorized_fixture="$(write_fixture access-exceptional-status-reviewer-authorized "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"abc123\"
  | .pr.mergeStateStatus = \"BLOCKED\"
  | .statusChecks += [{\"name\":\"Haystack / Review\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\",\"detailsUrl\":\"https://example.test/haystack\"}]
  | .reviewer.reason = \"forbidden\"
  | .reviewerChecks = [{\"name\":\"Haystack / Review\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\",\"detailsUrl\":\"https://example.test/haystack\"}]
  | .accessRestriction = {
      provider: \"haystack\",
      reason: \"forbidden\",
      source: \"reviewer-loop\",
      evidence: \"HTTP 403 from reviewer details URL\",
      remediationAttempted: true,
      cannotUnblockInTime: true,
      bypassReason: \"organization approval cannot complete before release window\"
    }
  | .authorization = {
      pullRequest: 42,
      headSha: \"abc123\",
      evidenceFingerprint: \"$exceptional_status_reviewer_fingerprint\",
      authorizedBy: \"lhpaul\",
      authorizedAt: \"2026-07-29T12:00:00Z\",
      authorizationText: \"Approve admin merge for PR #42\"
    }
  | .bypassAudit = {
      present: true,
      state: \"authorized_pending_attempt\",
      evidenceFingerprint: \"$exceptional_status_reviewer_fingerprint\",
      commentId: \"IC_kwDO\"
    }
")"
run_test "reviewer_status_check_does_not_block_exceptional_bypass" "exceptional_bypass_authorized:true" "$(
  "$GATE" --input "$exceptional_with_status_reviewer_authorized_fixture" --json |
    jq -r '.decision + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

exceptional_missing_label_fixture="$(write_fixture access-exceptional-missing-label "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"abc123\"
  | .pr.mergeStateStatus = \"BLOCKED\"
  | .pr.labels = [\"ready-for-regression\"]
  | .reviewer.reason = \"forbidden\"
  | .reviewerChecks = [{\"name\":\"Haystack / Review\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\",\"detailsUrl\":\"https://example.test/haystack\"}]
  | .accessRestriction = {
      provider: \"haystack\",
      reason: \"forbidden\",
      source: \"reviewer-loop\",
      evidence: \"HTTP 403 from reviewer details URL\",
      remediationAttempted: true,
      cannotUnblockInTime: true,
      bypassReason: \"organization approval cannot complete before release window\"
    }
  | .authorization = {
      pullRequest: 42,
      headSha: \"abc123\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      authorizedBy: \"lhpaul\",
      authorizedAt: \"2026-07-29T12:00:00Z\",
      authorizationText: \"Approve admin merge for PR #42\"
    }
  | .bypassAudit = {
      present: true,
      state: \"authorized_pending_attempt\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      commentId: \"IC_kwDO\"
    }
")"
run_test "reviewer_access_exceptional_does_not_bypass_missing_labels" "blocked:false" "$(
  "$GATE" --input "$exceptional_missing_label_fixture" --json |
    jq -r '.decision + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

exceptional_not_mergeable_fixture="$(write_fixture access-exceptional-not-mergeable "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"abc123\"
  | .pr.mergeable = \"CONFLICTING\"
  | .pr.mergeStateStatus = \"BLOCKED\"
  | .reviewer.reason = \"forbidden\"
  | .reviewerChecks = [{\"name\":\"Haystack / Review\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\",\"detailsUrl\":\"https://example.test/haystack\"}]
  | .accessRestriction = {
      provider: \"haystack\",
      reason: \"forbidden\",
      source: \"reviewer-loop\",
      evidence: \"HTTP 403 from reviewer details URL\",
      remediationAttempted: true,
      cannotUnblockInTime: true,
      bypassReason: \"organization approval cannot complete before release window\"
    }
  | .authorization = {
      pullRequest: 42,
      headSha: \"abc123\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      authorizedBy: \"lhpaul\",
      authorizedAt: \"2026-07-29T12:00:00Z\",
      authorizationText: \"Approve admin merge for PR #42\"
    }
  | .bypassAudit = {
      present: true,
      state: \"authorized_pending_attempt\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      commentId: \"IC_kwDO\"
    }
")"
run_test "reviewer_access_exceptional_requires_mergeable_pr" "blocked:false" "$(
  "$GATE" --input "$exceptional_not_mergeable_fixture" --json |
    jq -r '.decision + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

access_without_reviewer_checks_fixture="$(write_fixture access-without-reviewer-checks '
  .pr.headSha = "abc123"
  | .reviewer.reason = "forbidden"
  | .accessRestriction = {reason:"forbidden", evidence:"HTTP 403", remediationAttempted:true, cannotUnblockInTime:true, bypassReason:"release window"}
')"
run_test "reviewer_access_requires_reviewer_check_evidence" "blocked:insufficient_evidence" "$(
  "$GATE" --input "$access_without_reviewer_checks_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

missing_denial_fixture="$(write_fixture access-missing-denial '
  .pr.headSha = "abc123"
  | .pr.mergeStateStatus = "BLOCKED"
  | .reviewer.reason = ""
  | .reviewerChecks = [{"name":"Haystack / Review","status":"COMPLETED","conclusion":"FAILURE"}]
')"
run_test "reviewer_access_missing_denial_fails_closed" "blocked:insufficient_evidence" "$(
  "$GATE" --input "$missing_denial_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

unrelated_denial_evidence_fixture="$(write_fixture access-unrelated-denial-evidence '
  .pr.headSha = "abc123"
  | .pr.mergeStateStatus = "BLOCKED"
  | .reviewer.reason = ""
  | .reviewerChecks = [{"name":"Haystack / Review","status":"COMPLETED","conclusion":"FAILURE"}]
  | .accessRestriction = {reason:"", evidence:"https://example.test/api/v3/forbidden-resource?id=4032", remediationAttempted:true, cannotUnblockInTime:true, bypassReason:"release window"}
')"
run_test "reviewer_access_unrelated_denial_text_fails_closed" "blocked:insufficient_evidence" "$(
  "$GATE" --input "$unrelated_denial_evidence_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

access_with_ci_failure_fixture="$(write_fixture access-ci-failure '
  .pr.headSha = "abc123"
  | .pr.mergeStateStatus = "BLOCKED"
  | .statusChecks[0].conclusion = "FAILURE"
  | .reviewer.reason = "forbidden"
  | .reviewerChecks = [{"name":"Haystack / Review","status":"COMPLETED","conclusion":"FAILURE"}]
  | .accessRestriction = {reason:"forbidden", evidence:"HTTP 403", remediationAttempted:true, cannotUnblockInTime:true, bypassReason:"release window"}
')"
run_test "reviewer_access_ci_failure_takes_precedence" "fix_required:ci_blocker" "$(
  "$GATE" --input "$access_with_ci_failure_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

access_with_status_reviewer_check_fixture="$(write_fixture access-status-reviewer-check '
  .pr.headSha = "abc123"
  | .pr.mergeStateStatus = "BLOCKED"
  | .statusChecks = [
      {"name":"guard","status":"COMPLETED","conclusion":"SUCCESS"},
      {"name":"Haystack / Review","status":"COMPLETED","conclusion":"FAILURE"}
    ]
  | .reviewer.reason = "forbidden"
  | .reviewerChecks = [{"name":"Haystack / Review","status":"COMPLETED","conclusion":"FAILURE"}]
  | .accessRestriction = {reason:"forbidden", evidence:"HTTP 403", remediationAttempted:false, cannotUnblockInTime:false, bypassReason:""}
')"
run_test "reviewer_access_status_reviewer_check_not_ci_blocker" "human_required:access_restricted" "$(
  "$GATE" --input "$access_with_status_reviewer_check_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

access_with_review_blocker_fixture="$(write_fixture access-review-blocker '
  .pr.headSha = "abc123"
  | .pr.mergeStateStatus = "BLOCKED"
  | .reviewer.reason = "forbidden"
  | .reviewer.blockingCount = 1
  | .reviewerChecks = [{"name":"Haystack / Review","status":"COMPLETED","conclusion":"FAILURE"}]
  | .accessRestriction = {reason:"forbidden", evidence:"HTTP 403", remediationAttempted:true, cannotUnblockInTime:true, bypassReason:"release window"}
')"
run_test "reviewer_access_blocking_finding_takes_precedence" "fix_required:review_blocker" "$(
  "$GATE" --input "$access_with_review_blocker_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

text_output="$("$GATE" --input "$risk_fixture")"
run_test "text_output_includes_decision" "yes" "$(grep -q 'Decision: human_required' <<< "$text_output" && echo yes || echo no)"

exceptional_text_output="$("$GATE" --input "$exceptional_authorized_fixture")"
run_test "text_output_includes_exceptional_admin_flag" "yes" "$(grep -q 'Exceptional admin merge permitted: true' <<< "$exceptional_text_output" && echo yes || echo no)"
run_test "text_output_includes_reviewer_access_classification" "yes" "$(grep -q 'Reviewer access classification: exceptional_bypass_authorized' <<< "$exceptional_text_output" && echo yes || echo no)"

run_test "json_read_only_guarantee" "yes" "$(
  "$GATE" --input "$clean_fixture" --json | jq -e '.readOnlyGuarantee | test("No reviewer-loop")' >/dev/null && echo yes || echo no
)"
run_test "no_mutating_gh_commands" "no" "$(
  grep -Eq '(^issue edit|^pr create|^pr merge|^pr edit|^pr comment|^project item-edit|^project item-add|mutation)' "$CALL_LOG" && echo yes || echo no
)"

# --- bulk advisory warning (non-fatal) ---

# Fixture: advisory_count=6 but only 1 advisories[] entry — should warn, not block
bulk_advisory_gate_fixture="$(write_fixture bulk-advisory-gate \
  '.reviewer.advisoryCount = 6 | .advisories = [{"source": "haystack", "category": "Minor", "decision": "accepted", "rationale": "reviewed and accepted"}]')"

bulk_gate_stderr="$("$GATE" --input "$bulk_advisory_gate_fixture" --json 2>&1 >/dev/null)"
run_test "bulk_advisory_gate_emits_warning" "yes" \
  "$(grep -q 'per-finding review' <<< "$bulk_gate_stderr" && echo yes || echo no)"
run_test "bulk_advisory_gate_does_not_block_merge" "merge_allowed" \
  "$(decision_for "$bulk_advisory_gate_fixture")"

# Fixture: advisory_count=0 — no warning even with no advisories[] entries
no_advisory_gate_fixture="$(write_fixture no-advisory-gate '.reviewer.advisoryCount = 0 | .advisories = []')"
no_advisory_gate_stderr="$("$GATE" --input "$no_advisory_gate_fixture" --json 2>&1 >/dev/null)"
run_test "no_bulk_advisory_warn_when_count_zero" "yes" \
  "$(printf '%s' "$no_advisory_gate_stderr" | wc -c | tr -d ' ' | grep -qx '0' && echo yes || echo no)"

# Fixture: advisory_count=2 with two entries — no warning (each finding has its own entry)
per_finding_gate_fixture="$(write_fixture per-finding-gate \
  '.reviewer.advisoryCount = 2 | .advisories = [{"source": "haystack", "category": "Minor", "decision": "accepted", "rationale": "reason A"}, {"source": "haystack", "category": "Advisory", "decision": "fixed", "rationale": ""}]')"
per_finding_gate_stderr="$("$GATE" --input "$per_finding_gate_fixture" --json 2>&1 >/dev/null)"
run_test "no_bulk_advisory_warn_when_one_entry_per_finding" "yes" \
  "$(printf '%s' "$per_finding_gate_stderr" | wc -c | tr -d ' ' | grep -qx '0' && echo yes || echo no)"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
