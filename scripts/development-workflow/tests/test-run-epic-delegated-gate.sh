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
  api\ repos/example/mobile-app/issues/comments/12345)
    jq -n \
      --arg body "${MOCK_GH_AUTHORIZATION_BODY:-}" \
      --arg user_type "${MOCK_GH_AUTHORIZATION_USER_TYPE:-User}" \
      --arg association "${MOCK_GH_AUTHORIZATION_ASSOCIATION:-MEMBER}" \
      --arg issue_url "${MOCK_GH_AUTHORIZATION_ISSUE_URL:-https://api.github.com/repos/example/mobile-app/issues/42}" \
      '{id: 12345, user: {login: "lhpaul", type: $user_type}, author_association: $association, issue_url: $issue_url, created_at: "2026-07-29T12:00:00Z", body: $body}'
    ;;
  api\ repos/example/mobile-app/pulls/42/reviews/12345)
    jq -n \
      --arg body "${MOCK_GH_AUTHORIZATION_BODY:-}" \
      --arg user_type "${MOCK_GH_AUTHORIZATION_USER_TYPE:-User}" \
      --arg association "${MOCK_GH_AUTHORIZATION_ASSOCIATION:-MEMBER}" \
      --arg pull_request_url "${MOCK_GH_AUTHORIZATION_PULL_REQUEST_URL:-https://api.github.com/repos/example/mobile-app/pulls/42}" \
      '{id: 12345, user: {login: "lhpaul", type: $user_type}, author_association: $association, pull_request_url: $pull_request_url, submitted_at: "2026-07-29T12:00:00Z", body: $body}'
    ;;
  api\ repos/example/mobile-app/pulls/comments/12345)
    jq -n \
      --arg body "${MOCK_GH_AUTHORIZATION_BODY:-}" \
      --arg user_type "${MOCK_GH_AUTHORIZATION_USER_TYPE:-User}" \
      --arg association "${MOCK_GH_AUTHORIZATION_ASSOCIATION:-MEMBER}" \
      --arg pull_request_url "${MOCK_GH_AUTHORIZATION_PULL_REQUEST_URL:-https://api.github.com/repos/example/mobile-app/pulls/42}" \
      '{id: 12345, user: {login: "lhpaul", type: $user_type}, author_association: $association, pull_request_url: $pull_request_url, created_at: "2026-07-29T12:00:00Z", body: $body}'
    ;;
  api\ repos/example/mobile-app/collaborators/lhpaul/permission)
    jq -n --arg permission "${MOCK_GH_AUTHORIZATION_PERMISSION:-admin}" '{permission: $permission}'
    ;;
  api\ repos/example/mobile-app/issues/comments/54321)
    jq -n \
      --arg body "${MOCK_GH_SECURITY_DECISION_BODY:-}" \
      --arg user_type "${MOCK_GH_SECURITY_DECISION_USER_TYPE:-User}" \
      --arg association "${MOCK_GH_SECURITY_DECISION_ASSOCIATION:-MEMBER}" \
      --arg issue_url "${MOCK_GH_SECURITY_DECISION_ISSUE_URL:-https://api.github.com/repos/example/mobile-app/issues/42}" \
      --arg created_at "${MOCK_GH_SECURITY_DECISION_CREATED_AT:-2026-08-05T12:00:00Z}" \
      '{id: 54321, user: {login: "secreviewer", type: $user_type}, author_association: $association, issue_url: $issue_url, created_at: $created_at, body: $body}'
    ;;
  api\ repos/example/mobile-app/collaborators/secreviewer/permission)
    jq -n --arg permission "${MOCK_GH_SECURITY_DECISION_PERMISSION:-write}" '{permission: $permission}'
    ;;
  api\ --paginate\ --slurp\ repos/example/mobile-app/issues/42/comments?per_page=100)
    if [ -n "${MOCK_GH_BYPASS_AUDIT_BODY:-}" ]; then
      jq -n --arg body "$MOCK_GH_BYPASS_AUDIT_BODY" '[[{id: 67890, user: {login: "lhpaul"}, created_at: "2026-07-29T12:01:00Z", body: $body}]]'
    else
      printf '[[]]\n'
    fi
    ;;
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
  "advisories": [
    {"source": "codex", "category": "advisory", "decision": "accepted", "rationale": "reviewed and accepted for delegated gate fixture"}
  ],
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

# --- incomplete .pr identity input must error, not degrade to a worst-case
# --- decision full of false blockers (issue #1435) ---

missing_pr_object_fixture="$(write_fixture missing-pr-object 'del(.pr)')"
run_fails_contains "rejects_missing_pr_object" \
  "evidence file's .pr object is missing required identity field(s): pr" \
  "$GATE" --input "$missing_pr_object_fixture" --json

# Exact reproduction of the reported evidence shape from issue #1435: the
# evidence-assembly step ran but never populated .pr.number/.headRefName/
# .baseRefName.
unpopulated_pr_fixture="$(write_fixture unpopulated-pr \
  '.pr.number = null | .pr.headRefName = "" | .pr.baseRefName = ""')"
run_fails_contains "rejects_unpopulated_pr_identity" \
  "evidence file's .pr object is missing required identity field(s): pr.number, pr.headRefName, pr.baseRefName" \
  "$GATE" --input "$unpopulated_pr_fixture" --json
run_test "unpopulated_pr_identity_no_worst_case_reasons" "no" "$(
  set +e
  output="$("$GATE" --input "$unpopulated_pr_fixture" --json 2>&1)"
  set -e
  grep -q '"decision": "human_required"' <<< "$output" && echo yes || echo no
)"

partial_pr_identity_fixture="$(write_fixture partial-pr-identity 'del(.pr.baseRefName)')"
run_fails_contains "rejects_partial_pr_identity" \
  "evidence file's .pr object is missing required identity field(s): pr.baseRefName" \
  "$GATE" --input "$partial_pr_identity_fixture" --json

# Whitespace-only identity strings are not a legitimate value -- trim_text()
# must treat them the same as empty.
whitespace_pr_identity_fixture="$(write_fixture whitespace-pr-identity \
  '.pr.headRefName = "   " | .pr.baseRefName = "\t\n"')"
run_fails_contains "rejects_whitespace_only_pr_identity" \
  "evidence file's .pr object is missing required identity field(s): pr.headRefName, pr.baseRefName" \
  "$GATE" --input "$whitespace_pr_identity_fixture" --json

# Non-scalar / wrong-typed identity values must fail the same way as absent
# ones -- a coerced-via-tostring value (e.g. a number for headRefName) must
# not be accepted as a valid string, and .pr.number must be a positive
# integer, not merely non-null.
string_number_fixture="$(write_fixture string-number-pr-identity '.pr.number = "42"')"
run_fails_contains "rejects_string_pr_number" \
  "evidence file's .pr object is missing required identity field(s): pr.number" \
  "$GATE" --input "$string_number_fixture" --json

zero_number_fixture="$(write_fixture zero-pr-identity '.pr.number = 0')"
run_fails_contains "rejects_zero_pr_number" \
  "evidence file's .pr object is missing required identity field(s): pr.number" \
  "$GATE" --input "$zero_number_fixture" --json

negative_number_fixture="$(write_fixture negative-pr-identity '.pr.number = -1')"
run_fails_contains "rejects_negative_pr_number" \
  "evidence file's .pr object is missing required identity field(s): pr.number" \
  "$GATE" --input "$negative_number_fixture" --json

non_integer_number_fixture="$(write_fixture non-integer-pr-identity '.pr.number = 3.5')"
run_fails_contains "rejects_non_integer_pr_number" \
  "evidence file's .pr object is missing required identity field(s): pr.number" \
  "$GATE" --input "$non_integer_number_fixture" --json

numeric_branch_name_fixture="$(write_fixture numeric-branch-name-pr-identity '.pr.headRefName = 918')"
run_fails_contains "rejects_numeric_head_ref_name" \
  "evidence file's .pr object is missing required identity field(s): pr.headRefName" \
  "$GATE" --input "$numeric_branch_name_fixture" --json

object_branch_name_fixture="$(write_fixture object-branch-name-pr-identity '.pr.baseRefName = {}')"
run_fails_contains "rejects_object_base_ref_name" \
  "evidence file's .pr object is missing required identity field(s): pr.baseRefName" \
  "$GATE" --input "$object_branch_name_fixture" --json

array_branch_name_fixture="$(write_fixture array-branch-name-pr-identity '.pr.headRefName = []')"
run_fails_contains "rejects_array_head_ref_name" \
  "evidence file's .pr object is missing required identity field(s): pr.headRefName" \
  "$GATE" --input "$array_branch_name_fixture" --json

# .pr.inScope must be a literal boolean when present -- a value that merely
# coerces to falsy/truthy via jq's `//` operator (null, a string, a number,
# an object) must not silently decide the scope outcome either way.
null_in_scope_fixture="$(write_fixture null-in-scope '.pr.inScope = null')"
run_fails_contains "rejects_null_in_scope" \
  "evidence file's .pr.inScope field is present but not a boolean (got type: null)" \
  "$GATE" --input "$null_in_scope_fixture" --json

string_in_scope_fixture="$(write_fixture string-in-scope '.pr.inScope = "false"')"
run_fails_contains "rejects_string_in_scope" \
  "evidence file's .pr.inScope field is present but not a boolean (got type: string)" \
  "$GATE" --input "$string_in_scope_fixture" --json

numeric_in_scope_fixture="$(write_fixture numeric-in-scope '.pr.inScope = 0')"
run_fails_contains "rejects_numeric_in_scope" \
  "evidence file's .pr.inScope field is present but not a boolean (got type: number)" \
  "$GATE" --input "$numeric_in_scope_fixture" --json

object_in_scope_fixture="$(write_fixture object-in-scope '.pr.inScope = {}')"
run_fails_contains "rejects_object_in_scope" \
  "evidence file's .pr.inScope field is present but not a boolean (got type: object)" \
  "$GATE" --input "$object_in_scope_fixture" --json

# Genuinely complete input (full .pr identity, as every fixture below
# supplies) with a real blocker must still report it — see
# "requires_human_review_label" -> blocked below, which proves the
# validation step does not swallow real findings.

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
run_test "candidate_not_in_scope_is_not_applicable" "not_applicable" "$(decision_for "$out_of_scope_fixture")"
run_test "candidate_not_in_scope_has_single_scope_reason" "1:candidate PR is not in the resolved run-epic scope" "$(
  "$GATE" --input "$out_of_scope_fixture" --json |
    jq -r '(.reasons | length | tostring) + ":" + .reasons[0]'
)"
run_test "candidate_not_in_scope_merge_not_permitted" "false" "$("$GATE" --input "$out_of_scope_fixture" --json | jq -r '.mergePermitted')"
run_test "candidate_not_in_scope_reviewer_access_not_applicable" "not_applicable" "$("$GATE" --input "$out_of_scope_fixture" --json | jq -r '.reviewerAccess.classification')"

# When the caller never populates .pr.inScope at all (e.g. a Protocol 90
# explicit-batch item run through the shared Gate 5 path, which has no
# resolved run-epic scope to be in or out of), the scope check must be
# skipped entirely rather than defaulting to "out of scope" and blocking.
scope_absent_fixture="$(write_fixture scope-absent 'del(.pr.inScope)')"
run_test "missing_scope_field_does_not_block" "merge_allowed" "$(decision_for "$scope_absent_fixture")"
run_test "missing_scope_field_reason_absent" "false" "$(reason_match_for "$scope_absent_fixture" "not in the resolved")"

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

ci_reviewer_name_collision_fixture="$(write_fixture ci-reviewer-name-collision '
  .statusChecks = [
    {"name": "shared", "workflowName": "CI", "status": "COMPLETED", "conclusion": "FAILURE"},
    {"name": "other", "workflowName": "CI", "status": "COMPLETED", "conclusion": "SUCCESS"}
  ]
  | .reviewerChecks = [{"name": "shared", "workflowName": "Reviewer", "status": "COMPLETED", "conclusion": "FAILURE"}]
  | .reviewer.reason = "forbidden"
')"
run_test "ci_reviewer_name_collision_keeps_ci_check" "fix_required" "$(decision_for "$ci_reviewer_name_collision_fixture")"

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
incomplete_advisory_fixture="$(write_fixture advisory-incomplete-evidence '.reviewer.advisoryCount = 2 | .advisories = [{"source": "codex", "decision": "accepted", "rationale": "accepted one"}]')"
run_test "incomplete_advisory_evidence_requires_fix" "fix_required" "$(decision_for "$incomplete_advisory_fixture")"
accepted_advisory_no_rationale_fixture="$(write_fixture advisory-accepted-no-rationale '.reviewer.advisoryCount = 1 | .advisories = [{"source": "codex", "decision": "accepted", "rationale": ""}]')"
run_test "accepted_advisory_without_entry_rationale_requires_fix" "fix_required" "$(decision_for "$accepted_advisory_no_rationale_fixture")"
accepted_advisory_whitespace_rationale_fixture="$(write_fixture advisory-accepted-whitespace-rationale '.reviewer.advisoryCount = 1 | .advisories = [{"source": "codex", "decision": "accepted", "rationale": "   "}]')"
run_test "accepted_advisory_with_whitespace_rationale_requires_fix" "fix_required" "$(decision_for "$accepted_advisory_whitespace_rationale_fixture")"
advisory_no_disposition_fixture="$(write_fixture advisory-no-disposition '.reviewer.advisoryCount = 1 | .advisories = [{"source": "codex", "rationale": "reviewed"}]')"
run_test "advisory_without_disposition_requires_fix" "fix_required" "$(decision_for "$advisory_no_disposition_fixture")"

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

invalid_state_checkpoint_fixture="$(write_fixture invalid-state-checkpoint '.item.number = 1023 | .pr.headRefName = "feature/1023-human-checkpoint-gates" | .policy.checkpoints = [{"item_number":1023,"stage":"implementation","domain":"technical","reason":"typo state","required_human_action":"approve delegated gate checkpoint handling","satisfaction_state":"pendng"}]')"
run_test "invalid_checkpoint_state_requires_human" "human_required" "$(decision_for "$invalid_state_checkpoint_fixture")"
run_test "invalid_checkpoint_state_reason_names_enum" "true" "$(reason_match_for "$invalid_state_checkpoint_fixture" "invalid checkpoint satisfaction_state")"

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
  | .pr.headSha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
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
  | .pr.headSha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
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
structured_authorization_text="I authorize gh pr merge 42 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa for PR #42 at head aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa with evidence fingerprint $authorization_fingerprint"
export MOCK_GH_AUTHORIZATION_BODY="$structured_authorization_text"
export MOCK_GH_BYPASS_AUDIT_BODY=""
trusted_authorization_event_filter="| .authorizationEvents = [{
  source: \"github\",
  type: \"issue_comment\",
  id: 12345,
  pullRequest: 42,
  headSha: \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",
  evidenceFingerprint: \"$authorization_fingerprint\",
  author: \"lhpaul\",
  authorType: \"User\",
  authorAssociation: \"MEMBER\",
  authorPermission: \"admin\",
  targetPullRequest: true,
  createdAt: \"2026-07-29T12:00:00Z\",
  body: \"$structured_authorization_text\"
}]"
run_test "reviewer_access_requires_named_authorization" "human_required:authorization_required" "$(printf '%s\n' "$authorization_required_output" | jq -r '.decision + ":" + .reviewerAccess.classification')"
run_test "reviewer_access_reports_fingerprint" "yes" "$(grep -Eq '^sha256:[0-9a-f]{64}$' <<< "$authorization_fingerprint" && echo yes || echo no)"

authorization_stale_fixture="$(write_fixture authorization-stale "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"
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
      authorizationText: \"$structured_authorization_text\"
    }
")"
run_test "reviewer_access_stale_authorization_blocks" "human_required:authorization_stale" "$(
  "$GATE" --input "$authorization_stale_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

audit_required_fixture="$(write_fixture access-audit-required "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"
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
      headSha: \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      authorizedBy: \"lhpaul\",
      authorizedAt: \"2026-07-29T12:00:00Z\",
      authorizationText: \"$structured_authorization_text\"
    }
  $trusted_authorization_event_filter
")"
run_test "reviewer_access_requires_pre_attempt_audit" "human_required:audit_required" "$(
  "$GATE" --input "$audit_required_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

exceptional_authorized_fixture="$(write_fixture access-exceptional-authorized "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"
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
      headSha: \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      authorizedBy: \"lhpaul\",
      authorizedAt: \"2026-07-29T12:00:00Z\",
      authorizationText: \"$structured_authorization_text\"
    }
  $trusted_authorization_event_filter
  | .bypassAudit = {
      present: true,
      state: \"authorized_pending_attempt\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      commentId: \"IC_kwDO\"
    }
")"
export MOCK_GH_BYPASS_AUDIT_BODY="<!-- reviewer-access-bypass -->
## Reviewer Access Bypass Audit

- State: authorized_pending_attempt
- Authorized by: lhpaul
- Authorized at: 2026-07-29T12:00:00Z
- Authorization text: $structured_authorization_text
- PR: #42
- Head SHA: \`aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\`
- Evidence fingerprint: \`$authorization_fingerprint\`
- Proposed action: \`gh pr merge 42 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\`"
run_test "reviewer_access_exceptional_authorization_is_separate_result" "exceptional_bypass_authorized:false:true:gh pr merge 42 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$(
  "$GATE" --input "$exceptional_authorized_fixture" --json |
    jq -r '.decision + ":" + (.mergePermitted|tostring) + ":" + (.exceptionalAdminMergePermitted|tostring) + ":" + .reviewerAccess.proposedAction'
)"

spoofed_bypass_audit_body="<!-- reviewer-access-bypass -->
## Reviewer Access Bypass Audit

- State: rolled_back
- Authorized by: lhpaul
- Authorized at: 2026-07-29T12:00:00Z
- Authorization text: $structured_authorization_text
- PR: #42
- Head SHA: \`aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\`
- Evidence fingerprint: \`$authorization_fingerprint\`
- Proposed action: \`gh pr merge 42 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\`

### Evidence

- Bypass reason: embedded stale lines should not qualify
- State: authorized_pending_attempt
- PR: #42
- Head SHA: \`aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\`
- Evidence fingerprint: \`$authorization_fingerprint\`
- Proposed action: \`gh pr merge 42 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\`"
run_test "reviewer_access_spoofed_audit_body_blocks_bypass" "human_required:audit_required:false" "$(
  MOCK_GH_BYPASS_AUDIT_BODY="$spoofed_bypass_audit_body" "$GATE" --input "$exceptional_authorized_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

review_comment_authorized_fixture="$TMP_ROOT/access-review-comment-authorized.json"
jq '.authorizationEvents[0].type = "review_comment"' \
  "$exceptional_authorized_fixture" > "$review_comment_authorized_fixture"
run_test "reviewer_access_accepts_review_comment_authorization_event" "exceptional_bypass_authorized:true" "$(
  "$GATE" --input "$review_comment_authorized_fixture" --json |
    jq -r '.decision + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

missing_trusted_authorization_event_fixture="$TMP_ROOT/access-missing-trusted-authorization-event.json"
jq 'del(.authorizationEvents)' \
  "$exceptional_authorized_fixture" > "$missing_trusted_authorization_event_fixture"
run_test "reviewer_access_missing_trusted_authorization_event_blocks_bypass" "human_required:authorization_required:false" "$(
  "$GATE" --input "$missing_trusted_authorization_event_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

mismatched_trusted_authorization_event_fixture="$TMP_ROOT/access-unavailable-trusted-authorization-event.json"
jq '.authorizationEvents[0].id = 99999' \
  "$exceptional_authorized_fixture" > "$mismatched_trusted_authorization_event_fixture"
run_test "reviewer_access_unavailable_trusted_authorization_event_blocks_bypass" "human_required:authorization_required:false" "$(
  "$GATE" --input "$mismatched_trusted_authorization_event_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

negative_authorization_comment_fixture="$TMP_ROOT/access-negative-authorization-comment.json"
jq '.' "$exceptional_authorized_fixture" > "$negative_authorization_comment_fixture"
run_test "reviewer_access_negative_authorization_comment_blocks_bypass" "human_required:authorization_required:false" "$(
  MOCK_GH_AUTHORIZATION_BODY="I do not authorize gh pr merge 42 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa for PR #42 at head aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa with evidence fingerprint $authorization_fingerprint" \
    "$GATE" --input "$negative_authorization_comment_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"
export MOCK_GH_AUTHORIZATION_BODY="$structured_authorization_text"

bot_authorization_comment_fixture="$TMP_ROOT/access-bot-authorization-comment.json"
jq '.' "$exceptional_authorized_fixture" > "$bot_authorization_comment_fixture"
run_test "reviewer_access_bot_authorization_comment_blocks_bypass" "human_required:authorization_required:false" "$(
  MOCK_GH_AUTHORIZATION_USER_TYPE="Bot" "$GATE" --input "$bot_authorization_comment_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

non_admin_authorization_comment_fixture="$TMP_ROOT/access-non-admin-authorization-comment.json"
jq '.' "$exceptional_authorized_fixture" > "$non_admin_authorization_comment_fixture"
run_test "reviewer_access_non_admin_authorization_comment_blocks_bypass" "human_required:authorization_required:false" "$(
  MOCK_GH_AUTHORIZATION_PERMISSION="read" "$GATE" --input "$non_admin_authorization_comment_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

wrong_pr_authorization_comment_fixture="$TMP_ROOT/access-wrong-pr-authorization-comment.json"
jq '.' "$exceptional_authorized_fixture" > "$wrong_pr_authorization_comment_fixture"
run_test "reviewer_access_wrong_pr_authorization_comment_blocks_bypass" "human_required:authorization_required:false" "$(
  MOCK_GH_AUTHORIZATION_ISSUE_URL="https://api.github.com/repos/example/mobile-app/issues/7" "$GATE" --input "$wrong_pr_authorization_comment_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

missing_named_authorization_fixture="$TMP_ROOT/access-missing-named-authorization.json"
jq 'del(.authorization.authorizedBy, .authorization.authorizedAt, .authorization.authorizationText)' \
  "$exceptional_authorized_fixture" > "$missing_named_authorization_fixture"
run_test "reviewer_access_missing_named_authorization_blocks_bypass" "human_required:authorization_required:false" "$(
  "$GATE" --input "$missing_named_authorization_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

blank_named_authorization_fixture="$TMP_ROOT/access-blank-named-authorization.json"
jq '.authorization.authorizedBy = "   " | .authorization.authorizedAt = "   " | .authorization.authorizationText = "   "' \
  "$exceptional_authorized_fixture" > "$blank_named_authorization_fixture"
run_test "reviewer_access_blank_named_authorization_blocks_bypass" "human_required:authorization_required:false" "$(
  "$GATE" --input "$blank_named_authorization_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

bad_timestamp_authorization_fixture="$TMP_ROOT/access-bad-timestamp-authorization.json"
jq '.authorization.authorizedAt = "not-a-date"' \
  "$exceptional_authorized_fixture" > "$bad_timestamp_authorization_fixture"
run_test "reviewer_access_bad_timestamp_authorization_blocks_bypass" "human_required:authorization_required:false" "$(
  "$GATE" --input "$bad_timestamp_authorization_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

missing_head_sha_fixture="$TMP_ROOT/access-missing-head-sha.json"
jq 'del(.pr.headSha) | .authorization.headSha = ""' \
  "$exceptional_authorized_fixture" > "$missing_head_sha_fixture"
run_test "reviewer_access_missing_head_sha_blocks_bypass" "blocked:insufficient_evidence:false" "$(
  "$GATE" --input "$missing_head_sha_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

exceptional_with_status_reviewer_fixture="$(write_fixture access-exceptional-status-reviewer "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"
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
structured_status_reviewer_authorization_text="I authorize gh pr merge 42 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa for PR #42 at head aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa with evidence fingerprint $exceptional_status_reviewer_fingerprint"
trusted_status_reviewer_authorization_event_filter="| .authorizationEvents = [{
  source: \"github\",
  type: \"issue_comment\",
  id: 12345,
  pullRequest: 42,
  headSha: \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",
  evidenceFingerprint: \"$exceptional_status_reviewer_fingerprint\",
  author: \"lhpaul\",
  authorType: \"User\",
  authorAssociation: \"MEMBER\",
  authorPermission: \"admin\",
  targetPullRequest: true,
  createdAt: \"2026-07-29T12:00:00Z\",
  body: \"$structured_status_reviewer_authorization_text\"
}]"
export MOCK_GH_AUTHORIZATION_BODY="$structured_status_reviewer_authorization_text"
export MOCK_GH_BYPASS_AUDIT_BODY="<!-- reviewer-access-bypass -->
## Reviewer Access Bypass Audit

- State: authorized_pending_attempt
- Authorized by: lhpaul
- Authorized at: 2026-07-29T12:00:00Z
- Authorization text: $structured_status_reviewer_authorization_text
- PR: #42
- Head SHA: \`aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\`
- Evidence fingerprint: \`$exceptional_status_reviewer_fingerprint\`
- Proposed action: \`gh pr merge 42 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\`"
exceptional_with_status_reviewer_authorized_fixture="$(write_fixture access-exceptional-status-reviewer-authorized "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"
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
      headSha: \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",
      evidenceFingerprint: \"$exceptional_status_reviewer_fingerprint\",
      authorizedBy: \"lhpaul\",
      authorizedAt: \"2026-07-29T12:00:00Z\",
      authorizationText: \"$structured_status_reviewer_authorization_text\"
    }
  $trusted_status_reviewer_authorization_event_filter
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
export MOCK_GH_AUTHORIZATION_BODY="$structured_authorization_text"
export MOCK_GH_BYPASS_AUDIT_BODY="<!-- reviewer-access-bypass -->
## Reviewer Access Bypass Audit

- State: authorized_pending_attempt
- Authorized by: lhpaul
- Authorized at: 2026-07-29T12:00:00Z
- Authorization text: $structured_authorization_text
- PR: #42
- Head SHA: \`aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\`
- Evidence fingerprint: \`$authorization_fingerprint\`
- Proposed action: \`gh pr merge 42 --admin --match-head-commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\`"

exceptional_clean_merge_state_fixture="$(write_fixture access-exceptional-clean-merge-state "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"
  | .pr.mergeStateStatus = \"CLEAN\"
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
      headSha: \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      authorizedBy: \"lhpaul\",
      authorizedAt: \"2026-07-29T12:00:00Z\",
      authorizationText: \"$structured_authorization_text\"
    }
  $trusted_authorization_event_filter
  | .bypassAudit = {
      present: true,
      state: \"authorized_pending_attempt\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      commentId: \"IC_kwDO\"
    }
")"
run_test "reviewer_access_clean_merge_state_uses_normal_merge" "merge_allowed:true:false" "$(
  "$GATE" --input "$exceptional_clean_merge_state_fixture" --json |
    jq -r '.decision + ":" + (.mergePermitted|tostring) + ":" + (.exceptionalAdminMergePermitted|tostring)'
)"

exceptional_missing_label_fixture="$(write_fixture access-exceptional-missing-label "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"
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
      headSha: \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      authorizedBy: \"lhpaul\",
      authorizedAt: \"2026-07-29T12:00:00Z\",
      authorizationText: \"$structured_authorization_text\"
    }
  $trusted_authorization_event_filter
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
  | .pr.headSha = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"
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
      headSha: \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",
      evidenceFingerprint: \"$authorization_fingerprint\",
      authorizedBy: \"lhpaul\",
      authorizedAt: \"2026-07-29T12:00:00Z\",
      authorizationText: \"$structured_authorization_text\"
    }
  $trusted_authorization_event_filter
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
  .pr.headSha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .reviewer.reason = "forbidden"
  | .accessRestriction = {reason:"forbidden", evidence:"HTTP 403", remediationAttempted:true, cannotUnblockInTime:true, bypassReason:"release window"}
')"
run_test "reviewer_access_requires_reviewer_check_evidence" "blocked:insufficient_evidence" "$(
  "$GATE" --input "$access_without_reviewer_checks_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

missing_denial_fixture="$(write_fixture access-missing-denial '
  .pr.headSha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .pr.mergeStateStatus = "BLOCKED"
  | .reviewer.reason = ""
  | .reviewerChecks = [{"name":"Haystack / Review","status":"COMPLETED","conclusion":"FAILURE"}]
')"
run_test "reviewer_access_missing_denial_fails_closed" "blocked:insufficient_evidence" "$(
  "$GATE" --input "$missing_denial_fixture" --json |
    jq -r '.decision + ":" + .reviewerAccess.classification'
)"

unrelated_denial_evidence_fixture="$(write_fixture access-unrelated-denial-evidence '
  .pr.headSha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
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
  .pr.headSha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
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
  .pr.headSha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
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
  .pr.headSha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
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

# Fixture: advisory_count=6 but only 1 advisories[] entry — should warn and block
bulk_advisory_gate_fixture="$(write_fixture bulk-advisory-gate \
  '.reviewer.advisoryCount = 6 | .advisories = [{"source": "haystack", "category": "Minor", "decision": "accepted", "rationale": "reviewed and accepted"}]')"

bulk_gate_stderr="$("$GATE" --input "$bulk_advisory_gate_fixture" --json 2>&1 >/dev/null)"
run_test "bulk_advisory_gate_emits_warning" "yes" \
  "$(grep -q 'per-finding review' <<< "$bulk_gate_stderr" && echo yes || echo no)"
run_test "bulk_advisory_gate_blocks_merge" "fix_required" \
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

# --- Security-sensitive advisory human decision requirement (issue #1432) ---

verify_decisions_for() {
  "$GATE" verify-security-advisory-decisions --input "$1"
}

SEC_HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SEC_ENFORCEMENT_FILE="scripts/development-workflow/workflow-branch-push-guard.sh"
security_advisory_pending_fixture="$(write_fixture security-advisory-pending "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"$SEC_HEAD_SHA\"
  | .securityAdvisories = [{
      id: \"sec-aaa111\",
      category: \"c\",
      matchedFile: \"$SEC_ENFORCEMENT_FILE\",
      status: \"pending\",
      headSha: \"$SEC_HEAD_SHA\",
      firstTrackedAt: \"2026-08-01T00:00:00Z\"
    }]
")"

# AC4/AC5/BR5: a pending security-sensitive finding blocks delegated merge
# with the exact "human_required" decision string, even with every other
# gate condition green, policy.mayMerge: true, and mode: delegated.
run_test "security_advisory_pending_requires_human" "human_required" "$(decision_for "$security_advisory_pending_fixture")"
run_test "security_advisory_pending_reason_present" "true" "$(reason_match_for "$security_advisory_pending_fixture" "^security_sensitive_advisory_pending: finding sec-aaa111")"
run_test "security_advisory_pending_blocks_merge_permitted" "false" "$(
  "$GATE" --input "$security_advisory_pending_fixture" --json | jq -r '.mergePermitted'
)"

# AC4/AC5: a fixed entry (cited commit) unblocks merge -- a verifiable fix
# remains available to the delegated agent without a human decision.
security_advisory_fixed_fixture="$(write_fixture security-advisory-fixed "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"$SEC_HEAD_SHA\"
  | .securityAdvisories = [{
      id: \"sec-aaa111\",
      category: \"c\",
      matchedFile: \"$SEC_ENFORCEMENT_FILE\",
      status: \"fixed\",
      headSha: \"$SEC_HEAD_SHA\",
      firstTrackedAt: \"2026-08-01T00:00:00Z\",
      fixCommit: \"deadbeef\"
    }]
")"
run_test "security_advisory_fixed_allows_merge" "merge_allowed" "$(decision_for "$security_advisory_fixed_fixture")"

# AC4/AC5/BR6: a verified human decision (via .securityAdvisoryDecisionEvents[]
# resolved by github_verified_security_advisory_decisions) also unblocks
# merge, without the delegated agent itself recording the disposition.
security_decision_text="I record a human decision for security-sensitive advisory finding sec-aaa111 on PR #42 at head ${SEC_HEAD_SHA}: accept — force-with-lease already enforced one layer up in the caller."
security_advisory_decision_event_fixture="$(write_fixture security-advisory-decision-event "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"$SEC_HEAD_SHA\"
  | .securityAdvisories = [{
      id: \"sec-aaa111\",
      category: \"c\",
      matchedFile: \"$SEC_ENFORCEMENT_FILE\",
      status: \"pending\",
      headSha: \"$SEC_HEAD_SHA\",
      firstTrackedAt: \"2026-08-01T00:00:00Z\"
    }]
  | .securityAdvisoryDecisionEvents = [{id: \"54321\", type: \"issue_comment\"}]
")"
export MOCK_GH_SECURITY_DECISION_BODY="$security_decision_text"
run_test "security_advisory_verified_human_decision_allows_merge" "merge_allowed" "$(decision_for "$security_advisory_decision_event_fixture")"
run_test "security_advisory_verify_subcommand_resolves_human_accepted" "human-accepted" "$(
  verify_decisions_for "$security_advisory_decision_event_fixture" | jq -r '.[0].decision'
)"
run_test "security_advisory_verify_subcommand_rationale" "force-with-lease already enforced one layer up in the caller." "$(
  verify_decisions_for "$security_advisory_decision_event_fixture" | jq -r '.[0].rationale'
)"
run_test "security_advisory_verify_subcommand_source_event_id" "54321" "$(
  verify_decisions_for "$security_advisory_decision_event_fixture" | jq -r '.[0].sourceEventId'
)"

# AC10/AC11/BR6: github_verified_security_advisory_decisions is fail-closed
# on every negative case; only a human author with write/admin permission,
# targeting this exact PR, at/after firstTrackedAt, resolves.
run_test "security_advisory_decision_admin_permission_resolves" "human-accepted" "$(
  MOCK_GH_SECURITY_DECISION_PERMISSION="admin" verify_decisions_for "$security_advisory_decision_event_fixture" | jq -r '.[0].decision // "none"'
)"
run_test "security_advisory_decision_bot_author_does_not_resolve" "[]" "$(
  MOCK_GH_SECURITY_DECISION_USER_TYPE="Bot" verify_decisions_for "$security_advisory_decision_event_fixture"
)"
run_test "security_advisory_decision_read_permission_does_not_resolve" "[]" "$(
  MOCK_GH_SECURITY_DECISION_PERMISSION="read" verify_decisions_for "$security_advisory_decision_event_fixture"
)"
run_test "security_advisory_decision_triage_permission_does_not_resolve" "[]" "$(
  MOCK_GH_SECURITY_DECISION_PERMISSION="triage" verify_decisions_for "$security_advisory_decision_event_fixture"
)"
run_test "security_advisory_decision_wrong_finding_id_does_not_resolve" "[]" "$(
  wrong_finding_fixture="$TMP_ROOT/security-advisory-wrong-finding.json"
  jq '.securityAdvisories[0].id = "sec-different"' "$security_advisory_decision_event_fixture" > "$wrong_finding_fixture"
  verify_decisions_for "$wrong_finding_fixture"
)"
run_test "security_advisory_decision_wrong_head_sha_does_not_resolve" "[]" "$(
  wrong_head_fixture="$TMP_ROOT/security-advisory-wrong-head.json"
  jq '.pr.headSha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" | .securityAdvisories[0].headSha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' \
    "$security_advisory_decision_event_fixture" > "$wrong_head_fixture"
  verify_decisions_for "$wrong_head_fixture"
)"
run_test "security_advisory_decision_unrelated_comment_does_not_resolve" "[]" "$(
  MOCK_GH_SECURITY_DECISION_BODY="just a generic comment, not a decision" verify_decisions_for "$security_advisory_decision_event_fixture"
)"
run_test "security_advisory_decision_generic_approval_does_not_resolve" "[]" "$(
  MOCK_GH_SECURITY_DECISION_BODY="LGTM, approved" verify_decisions_for "$security_advisory_decision_event_fixture"
)"
run_test "security_advisory_decision_wrong_target_pr_does_not_resolve" "[]" "$(
  MOCK_GH_SECURITY_DECISION_ISSUE_URL="https://api.github.com/repos/example/mobile-app/issues/7" verify_decisions_for "$security_advisory_decision_event_fixture"
)"
run_test "security_advisory_decision_stale_created_at_does_not_resolve" "[]" "$(
  MOCK_GH_SECURITY_DECISION_CREATED_AT="2026-07-01T00:00:00Z" verify_decisions_for "$security_advisory_decision_event_fixture"
)"
unset MOCK_GH_SECURITY_DECISION_BODY

# AC6/BR4: a blanket waiver of an unrelated pending-bounded-prelude checkpoint
# does not resolve a pending security-sensitive advisory finding; the two
# mechanisms are provably independent.
security_advisory_with_waived_checkpoint_fixture="$(write_fixture security-advisory-waived-checkpoint "
  .repository = \"example/mobile-app\"
  | .pr.headSha = \"$SEC_HEAD_SHA\"
  | .securityAdvisories = [{
      id: \"sec-aaa111\",
      category: \"c\",
      matchedFile: \"$SEC_ENFORCEMENT_FILE\",
      status: \"pending\",
      headSha: \"$SEC_HEAD_SHA\",
      firstTrackedAt: \"2026-08-01T00:00:00Z\"
    }]
  | .policy.checkpoints = [{
      item_number: 918,
      stage: \"implementation\",
      domain: \"technical\",
      reason: \"unrelated checkpoint\",
      required_human_action: \"unrelated approval\",
      satisfaction_state: \"waived\"
    }]
")"
run_test "waived_checkpoint_does_not_resolve_security_advisory" "human_required" "$(decision_for "$security_advisory_with_waived_checkpoint_fixture")"
run_test "waived_checkpoint_security_advisory_reason_still_present" "true" "$(reason_match_for "$security_advisory_with_waived_checkpoint_fixture" "^security_sensitive_advisory_pending:")"
run_test "waived_checkpoint_no_human_checkpoint_reason_for_this_finding" "false" "$(reason_match_for "$security_advisory_with_waived_checkpoint_fixture" "human_checkpoint_required")"

# AC7/BR4: label and stop-condition strings are textually distinct from the
# existing checkpoint label/stop-condition. Deliberately a literal
# string-inequality assertion (not only a grep) per the plan's Testing
# Strategy item 6.
# shellcheck disable=SC2050 # intentional literal-string inequality assertion
run_test "ac7_label_distinct_from_checkpoint_label" "yes" \
  "$([ "security-advisory-decision-required" != "human-checkpoint-required" ] && echo yes || echo no)"
# shellcheck disable=SC2050 # intentional literal-string inequality assertion
run_test "ac7_stop_condition_distinct_from_checkpoint_condition" "yes" \
  "$([ "security_sensitive_advisory_pending" != "human_checkpoint_required" ] && echo yes || echo no)"
run_test "ac7_reason_text_does_not_contain_checkpoint_condition" "no" "$(
  "$GATE" --input "$security_advisory_pending_fixture" --json |
    jq -r '.reasons[]' | grep -q 'human_checkpoint_required' && echo yes || echo no
)"

# AC8/AC9/BR8/BR9: absent/true .pr.inScope still evaluates and blocks;
# explicit false short-circuits to not_applicable exactly like every other
# reason (no new behavior specific to this feature in that branch).
security_advisory_scope_true_fixture="$TMP_ROOT/security-advisory-scope-true.json"
jq '.pr.inScope = true' "$security_advisory_pending_fixture" > "$security_advisory_scope_true_fixture"
run_test "security_advisory_scope_true_still_blocks" "human_required" "$(decision_for "$security_advisory_scope_true_fixture")"

security_advisory_scope_absent_fixture="$TMP_ROOT/security-advisory-scope-absent.json"
jq 'del(.pr.inScope)' "$security_advisory_pending_fixture" > "$security_advisory_scope_absent_fixture"
run_test "security_advisory_scope_absent_still_blocks" "human_required" "$(decision_for "$security_advisory_scope_absent_fixture")"

security_advisory_scope_false_fixture="$TMP_ROOT/security-advisory-scope-false.json"
jq '.pr.inScope = false' "$security_advisory_pending_fixture" > "$security_advisory_scope_false_fixture"
run_test "security_advisory_scope_false_not_applicable" "not_applicable" "$(decision_for "$security_advisory_scope_false_fixture")"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
