#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-epic-delegated-gate.sh --input <file> [--policy <file>] [--repo-root <path>] [--product-repo <name>] [--json]

Evaluates whether a delegated /run-epic candidate PR may proceed to the
repository merge protocol. The gate is read-only: it does not run reviewers,
poll CI, edit labels, update trackers, create comments, merge PRs, close
issues, or delete branches.

When --repo-root and --product-repo are supplied (or productRepo.name is present
in the evidence file), workflow_hub product repository ci_policy is loaded from
the resolver and applied when the evidence file omits ciPolicy/ci_policy.
EOF
}

input_file=""
policy_file=""
repo_root=""
product_repo=""
json_output=0

error_exit() {
  echo "ERROR: $*" >&2
  exit 1
}

require_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [ "${2#--}" != "$2" ]; then
    echo "$option requires a value." >&2
    usage >&2
    exit 64
  fi
}

load_input_json() {
  local file="$1"
  local raw
  if [ ! -f "$file" ]; then
    error_exit "input file not found: $file"
  fi
  if [ ! -s "$file" ]; then
    error_exit "input file is empty: $file"
  fi
  raw="$(jq -c '.' "$file" 2>/dev/null)" || error_exit "input file is not valid JSON: $file"
  if [ -z "$raw" ]; then
    error_exit "input file is not valid JSON: $file"
  fi
  printf '%s\n' "$raw"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --input)
      require_value "$@"
      input_file="$2"
      shift 2
      ;;
    --policy)
      require_value "$@"
      policy_file="$2"
      shift 2
      ;;
    --repo-root)
      require_value "$@"
      repo_root="$2"
      shift 2
      ;;
    --product-repo)
      require_value "$@"
      product_repo="$2"
      shift 2
      ;;
    --json)
      json_output=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [ -z "$input_file" ]; then
  echo "ERROR: --input is required." >&2
  exit 64
fi

state_json="$(load_input_json "$input_file")"

if [ -n "$policy_file" ]; then
  policy_json="$(load_input_json "$policy_file")"
  state_json="$(printf '%s\n' "$state_json" | jq --argjson policy "$policy_json" '.policy = $policy' 2>/dev/null)" || error_exit "failed to merge policy into state (jq parse error)"
  if [ -z "$state_json" ]; then
    error_exit "failed to merge policy into state (empty result)"
  fi
fi

effective_root="${repo_root:-$(workflow_repo_root)}"
state_json="$(workflow_merge_ci_policy_into_json "$state_json" "$effective_root" "$product_repo")"

material_evidence_json="$(printf '%s\n' "$state_json" | jq -cS '
  def reviewer_checks:
    if ((.reviewerChecks // null) | type) == "array" then .reviewerChecks
    elif ((.reviewer_checks // null) | type) == "array" then .reviewer_checks
    elif ((.reviewerChecksJson // null) | type) == "string" then ((try (.reviewerChecksJson | fromjson) catch []) // [])
    elif ((.reviewer_checks_json // null) | type) == "string" then ((try (.reviewer_checks_json | fromjson) catch []) // [])
    elif ((.ci.reviewerChecksJson // null) | type) == "string" then ((try (.ci.reviewerChecksJson | fromjson) catch []) // [])
    elif ((.ci.reviewer_checks_json // null) | type) == "string" then ((try (.ci.reviewer_checks_json | fromjson) catch []) // [])
    else [] end;
  {
    pr: {
      number: (.pr.number // null),
      repository: (.repository // .repo // ""),
      headSha: (.pr.headSha // .pr.head_sha // .pr.headRefOid // "")
    },
    ci: (.statusChecks // []),
    reviewer: {
      status: (.reviewer.status // ""),
      reason: (.reviewer.reason // ""),
      blockingCount: (.reviewer.blockingCount // .reviewer.blocking_count // 0)
    },
    reviewerChecks: reviewer_checks,
    accessRestriction: (.accessRestriction // .access_restriction // {})
  }
' 2>/dev/null)" || error_exit "failed to assemble material evidence fingerprint input"
material_fingerprint="$(printf '%s' "$material_evidence_json" | openssl dgst -sha256 -r | awk '{print $1}')"
state_json="$(printf '%s\n' "$state_json" | jq --arg fp "sha256:${material_fingerprint}" '.computedEvidenceFingerprint = $fp' 2>/dev/null)" || error_exit "failed to attach material evidence fingerprint"

decision_json="$(printf '%s\n' "$state_json" | jq '
  def policy: if (.policy | type) == "object" then .policy else {} end;
  def ci_policy: (.ciPolicy // .ci_policy // "required");
  def labels: (.pr.labels // []);
  def risk_blockers: (.risk.blockers // []);
  def risk_ci_only_blockers:
    (risk_blockers | length) > 0 and
    (risk_blockers | all(test("required CI|CI state|CI is not|CI check"; "i")));
  def has_label($name): labels | index($name) != null;
  def success_check:
    if (. | has("state")) and ((. | has("status")) | not) then
      ((.state // "") | ascii_downcase) == "success"
    else
      (((.status // "") | ascii_downcase) == "completed" and
       (((.conclusion // "") | ascii_downcase) as $conclusion |
        $conclusion == "success" or $conclusion == "skipped" or $conclusion == "neutral"))
    end;
  def implementation_branch:
    (.pr.headRefName // "") | test("^(feature|fix|refactor|hotfix|backport/hotfix)/");
  def graduation_pr:
    ((.pr.headRefName // "") | test("^develop-[^/]+$")) and
    ((.pr.baseRefName // "") == "develop");
  def graduation_approved:
    (policy.graduationApproved // false) == true;
  def stage_rank($stage):
    if $stage == "spec" then 1
    elif $stage == "plan" then 2
    elif $stage == "implementation" then 3
    else 0 end;
  def stage_from_branch($branch):
    if ($branch | test("^spec/")) then "spec"
    elif ($branch | test("^implementation-plan/")) then "plan"
    elif ($branch | test("^(feature|fix|refactor|hotfix|backport/hotfix)/")) then "implementation"
    else "implementation" end;
  def checkpoint_list:
    if ((.checkpoint_policy.effective // null) | type) == "array" then .checkpoint_policy.effective
    elif ((.checkpointPolicy.effective // null) | type) == "array" then .checkpointPolicy.effective
    elif ((try .policy.effectivePolicy.checkpoints catch null) | type) == "array" then .policy.effectivePolicy.checkpoints
    elif ((try .policy.effective_policy.checkpoints catch null) | type) == "array" then .policy.effective_policy.checkpoints
    elif ((try .invocation_policy.effective_policy.checkpoints catch null) | type) == "array" then .invocation_policy.effective_policy.checkpoints
    elif ((try .invocationPolicy.effectivePolicy.checkpoints catch null) | type) == "array" then .invocationPolicy.effectivePolicy.checkpoints
    elif ((try .policy.checkpoints catch null) | type) == "array" then .policy.checkpoints
    else [] end;
  def item_number:
    (.item.number // .item.issue_number // .item.issueNumber // null);
  def checkpoint_applies($cp; $item; $prStage):
    ($item != null)
    and (($cp.item_number | tonumber) == ($item | tonumber))
    and (($cp.satisfaction_state // "pending") == "pending")
    and (stage_rank($cp.stage) > 0)
    and (stage_rank($cp.stage) <= stage_rank($prStage));
  def pending_checkpoints:
    (stage_from_branch(.pr.headRefName // "")) as $prStage |
    (item_number) as $item |
    checkpoint_list
    | map(select(checkpoint_applies(.; $item; $prStage)));
  def checkpoint_reason($cp):
    "human_checkpoint_required: issue #" + (($cp.item_number // item_number) | tostring) +
    " " + (($cp.stage // "unknown") | tostring) + "/" + (($cp.domain // "unknown") | tostring) +
    ": " + (($cp.required_human_action // $cp.reason // "human confirmation required") | tostring);
  def risk_merge_permitted:
    if (.risk // {}) | has("mergePermitted") then .risk.mergePermitted
    elif (.risk // {}) | has("merge_permitted") then .risk.merge_permitted
    else false
    end;
  def reviewer_checks:
    if ((.reviewerChecks // null) | type) == "array" then .reviewerChecks
    elif ((.reviewer_checks // null) | type) == "array" then .reviewer_checks
    elif ((.reviewerChecksJson // null) | type) == "string" then ((try (.reviewerChecksJson | fromjson) catch []) // [])
    elif ((.reviewer_checks_json // null) | type) == "string" then ((try (.reviewer_checks_json | fromjson) catch []) // [])
    elif ((.ci.reviewerChecksJson // null) | type) == "string" then ((try (.ci.reviewerChecksJson | fromjson) catch []) // [])
    elif ((.ci.reviewer_checks_json // null) | type) == "string" then ((try (.ci.reviewer_checks_json | fromjson) catch []) // [])
    else [] end;
  def reviewer_check_name($check):
    ($check.name // $check.context // $check.workflowName // $check.provider // "unknown");
  def reviewer_check_non_green($check):
    (($check.conclusion // "") | ascii_downcase) as $conclusion |
    (($check.status // "") | ascii_downcase) as $status |
    (($check.state // "") | ascii_downcase) as $state |
    if ($state | length) > 0 and ($status | length) == 0 then
      ($state != "success")
    elif ($status | length) > 0 then
      ($status != "completed") or (($conclusion | IN("success", "skipped", "neutral")) | not)
    else
      ($conclusion | length) > 0 and (($conclusion | IN("success", "skipped", "neutral")) | not)
    end;
  def non_green_reviewer_checks:
    reviewer_checks | map(select(reviewer_check_non_green(.)));
  def access_obj: (.accessRestriction // .access_restriction // {});
  def access_denial_verified:
    (
      ((access_obj.reason // access_obj.providerReason // .reviewer.reason // "") | ascii_downcase | test("forbidden|unauthorized|access[_ -]?restricted|http 403|\\b403\\b"))
      or
      ((access_obj.evidence // access_obj.source // "") | tostring | ascii_downcase | test("forbidden|unauthorized|access[_ -]?restricted|http 403|\\b403\\b"))
    );
  def remediation_ready:
    (access_obj.remediationAttempted // access_obj.remediation_attempted // false) == true
    and (access_obj.cannotUnblockInTime // access_obj.cannot_unblock_in_time // false) == true
    and ((access_obj.bypassReason // access_obj.bypass_reason // "") | tostring | length) > 0;
  def authorization: (.authorization // .reviewerAccessAuthorization // .reviewer_access_authorization // {});
  def bypass_audit: (.bypassAudit // .bypass_audit // {});
  def reviewer_blocks:
    ((.reviewer.blockingCount // .reviewer.blocking_count // 0) | tonumber) > 0
    or ((.reviewer.status // "") | test("needs_fixes|failed|blocked"));
  def has_ci_blocker($reasons):
    any($reasons[]?; test("one or more required CI checks are not successful"; "i"));
  def reviewer_access_classification($reasons):
    (non_green_reviewer_checks) as $blockedChecks |
    (.computedEvidenceFingerprint // "") as $fingerprint |
    if has_ci_blocker($reasons) then "ci_blocker"
    elif reviewer_blocks then "review_blocker"
    elif (($blockedChecks | length) == 0) then "not_applicable"
    elif (access_denial_verified | not) then "insufficient_evidence"
    elif (remediation_ready | not) then "access_restricted"
    elif ((authorization.pullRequest // authorization.pull_request // null) == null) then "authorization_required"
    elif (((authorization.pullRequest // authorization.pull_request) | tostring) != ((.pr.number // "") | tostring)
       or ((authorization.headSha // authorization.head_sha // "") != (.pr.headSha // .pr.head_sha // .pr.headRefOid // ""))
       or ((authorization.evidenceFingerprint // authorization.evidence_fingerprint // "") != $fingerprint)) then "authorization_stale"
    elif ((bypass_audit.present // false) != true
       or ((bypass_audit.evidenceFingerprint // bypass_audit.evidence_fingerprint // "") != $fingerprint)
       or ((bypass_audit.state // "") != "authorized_pending_attempt")) then "audit_required"
    else "exceptional_bypass_authorized" end;
  def reviewer_access_summary($classification):
    {
      classification: $classification,
      pullRequest: (.pr.number // null),
      headSha: (.pr.headSha // .pr.head_sha // .pr.headRefOid // ""),
      evidenceFingerprint: (.computedEvidenceFingerprint // ""),
      blockedReviewerChecks: (non_green_reviewer_checks | map(reviewer_check_name(.))),
      primaryAction: (
        if $classification == "access_restricted" then "restore repository or organization App access and rerun reviewer evidence"
        elif $classification == "authorization_required" then "obtain fresh named human authorization for the exact PR, head SHA, and evidence fingerprint"
        elif $classification == "authorization_stale" then "refresh evidence and obtain a new named authorization"
        elif $classification == "audit_required" then "write and verify the pre-attempt reviewer access-bypass audit record"
        elif $classification == "exceptional_bypass_authorized" then "execute exactly the named gh pr merge --admin action once, then verify and update audit"
        elif $classification == "insufficient_evidence" then "refresh reviewer check and provider access-denial evidence"
        elif $classification == "ci_blocker" then "fix or complete CI before considering reviewer access restriction"
        elif $classification == "review_blocker" then "fix reviewer findings before considering reviewer access restriction"
        else "not applicable" end
      ),
      proposedAction: (if $classification == "exceptional_bypass_authorized" then "gh pr merge " + ((.pr.number // "") | tostring) + " --admin" else "" end)
    };
  def add_reason($reasons; $reason): $reasons + [$reason];
  def reason_count($reasons): $reasons | length;

  . as $state |
  [] as $reasons |
  (if (policy.delegateReview // false) != true
   then add_reason($reasons; "delegated review authority is missing")
   else $reasons end) as $reasons |
  (if (policy.mayMerge // false) != true
   then add_reason($reasons; "delegated merge authority is missing")
   else $reasons end) as $reasons |
  (if graduation_pr and (graduation_approved | not)
   then add_reason($reasons; "graduation_approval_required: PR #" + ((.pr.number // "unknown") | tostring) + " merges integration branch " + ((.pr.headRefName // "") | tostring) + " to " + ((.pr.baseRefName // "") | tostring) + "; run /graduate-development <slug> and record explicit human approval before delegated merge")
   else $reasons end) as $reasons |
  (if (.item.status // "") == "Backlog" and ((policy.mayStartBacklog // false) != true)
   then add_reason($reasons; "Backlog item cannot start without explicit may-start-backlog authority")
   else $reasons end) as $reasons |
  (if (.pr.inScope // false) != true
   then add_reason($reasons; "candidate PR is not in the resolved run-epic scope")
   else $reasons end) as $reasons |
  (if (if (.pr | has("isDraft")) then .pr.isDraft else true end) == true
   then add_reason($reasons; "PR is still draft")
   else $reasons end) as $reasons |
  (if has_label("ready-for-human-review") | not
   then add_reason($reasons; "ready-for-human-review label is missing")
   else $reasons end) as $reasons |
  (if implementation_branch and (has_label("ready-for-regression") | not)
   then add_reason($reasons; "implementation PR is missing ready-for-regression")
   else $reasons end) as $reasons |
  (if has_label("needs-setup")
   then add_reason($reasons; "needs-setup label is present")
   else $reasons end) as $reasons |
  (pending_checkpoints) as $pendingCheckpoints |
  (if ($pendingCheckpoints | length) > 0
   then $reasons + ($pendingCheckpoints | map(checkpoint_reason(.)))
   else $reasons end) as $reasons |
  (if has_label("human-checkpoint-required") and (($pendingCheckpoints | length) == 0)
   then add_reason($reasons; "human_checkpoint_required: human-checkpoint-required label is present; record satisfied or waived checkpoint evidence and remove the label before delegated merge")
   else $reasons end) as $reasons |
  (if (ci_policy == "none")
   then $reasons
   elif ((.statusChecks // []) | length) == 0
   then add_reason($reasons; "required CI state is missing")
   else $reasons end) as $reasons |
  (if (ci_policy == "none")
   then $reasons
   elif ((.statusChecks // []) | map(select(success_check | not)) | length) > 0
   then add_reason($reasons; "one or more required CI checks are not successful")
   else $reasons end) as $reasons |
  (if (.pr.mergeStateStatus // "") != "CLEAN"
   then add_reason($reasons; "PR merge state is not CLEAN")
   else $reasons end) as $reasons |
  (if ((.pr.unresolvedBlockingThreads // 0) | tonumber) > 0
   then add_reason($reasons; "unresolved blocking review threads remain")
   else $reasons end) as $reasons |
  (if ((.reviewer.blockingCount // 0) | tonumber) > 0 or ((.reviewer.status // "") | test("needs_fixes|failed|blocked"))
   then add_reason($reasons; "reviewer blocking findings require fixes")
   else $reasons end) as $reasons |
  (if ((.reviewer.acceptedAdvisoriesWithoutRationale // 0) | tonumber) > 0
   then add_reason($reasons; "accepted advisories require rationale")
   else $reasons end) as $reasons |
  (if (ci_policy == "none") and (risk_merge_permitted != true) and risk_ci_only_blockers
   then $reasons
   elif risk_merge_permitted != true
   then add_reason($reasons; "risk gate does not permit merge")
   else $reasons end) as $reasons |
  (if (.pr.auditDispositionPresent // false) != true
   then add_reason($reasons; "PR disposition audit is missing")
   else $reasons end) as $reasons |
  reviewer_access_classification($reasons) as $reviewerAccessClassification |
  reviewer_access_summary($reviewerAccessClassification) as $reviewerAccess |
  (reason_count($reasons)) as $count |
  {
    decision: (
      if $reviewerAccessClassification == "exceptional_bypass_authorized" then "exceptional_bypass_authorized"
      elif $reviewerAccessClassification == "ci_blocker" or $reviewerAccessClassification == "review_blocker" then "fix_required"
      elif $reviewerAccessClassification == "insufficient_evidence" then "blocked"
      elif ($reviewerAccessClassification | IN("access_restricted", "authorization_required", "authorization_stale", "audit_required")) then "human_required"
      elif $count == 0 then "merge_allowed"
      elif ($reasons | any(test("reviewer blocking|CI checks|unresolved blocking|advisories"))) then "fix_required"
      elif ($reasons | any(test("authority|risk gate|needs-setup|not in the resolved|Backlog|human_checkpoint_required|human-checkpoint|graduation_approval_required"))) then "human_required"
      else "blocked"
      end
    ),
    mergePermitted: ($count == 0 and $reviewerAccessClassification == "not_applicable"),
    exceptionalAdminMergePermitted: ($reviewerAccessClassification == "exceptional_bypass_authorized"),
    reasons: $reasons,
    reviewerAccess: $reviewerAccess,
    nextAction: (
      if $reviewerAccessClassification == "exceptional_bypass_authorized" then "execute exactly the named admin merge once, then verify merge state, cleanup, tracker reconciliation, and audit update"
      elif ($reviewerAccessClassification | IN("access_restricted", "authorization_required", "authorization_stale", "audit_required", "insufficient_evidence")) then $reviewerAccess.primaryAction
      elif $count == 0 then "record merge evidence and use the repository merge protocol"
      elif ($reasons | any(test("reviewer blocking|CI checks|unresolved blocking|advisories"))) then "remove readiness labels, fix, rerun validation, reviewer loop, CI loop, and this gate"
      elif ($reasons | any(test("human_checkpoint_required|human-checkpoint"))) then "stop for the named human checkpoint action, record satisfied or waived evidence, sync labels, and rerun this gate"
      elif ($reasons | any(test("graduation_approval_required"))) then "stop for explicit graduation approval via /graduate-development before mutating"
      elif ($reasons | any(test("authority|risk gate|needs-setup|not in the resolved|Backlog"))) then "stop for human authority or setup before mutating"
      else "block until required state is available"
      end
    ),
    pr: {
      number: (.pr.number // null),
      headRefName: (.pr.headRefName // ""),
      baseRefName: (.pr.baseRefName // "")
    },
    policy: policy,
    readOnlyGuarantee: "No reviewer-loop runs, CI polling, label edits, tracker updates, comments, merges, issue closure, or branch deletion were performed."
  }
' 2>/dev/null)" || error_exit "failed to evaluate delegated gate decision (jq parse error)"

if [ -z "$decision_json" ]; then
  error_exit "failed to evaluate delegated gate decision (empty result)"
fi

bulk_advisory_warning=""
bulk_advisory_warning="$(printf '%s\n' "$state_json" | jq -r '
  (.reviewer.advisoryCount // .reviewer.advisory_count // 0 | tonumber) as $count |
  (.advisories // [] | length) as $len |
  if $count > 0 and $len < $count then
    "WARN: advisory_count=" + ($count | tostring) +
    " but only " + ($len | tostring) + " advisories[] entries recorded; protocol requires per-finding review (Step 8 item 5)"
  else "" end
' 2>/dev/null)" || error_exit "failed to check advisory coverage (jq parse error)"

if [ "$json_output" -eq 1 ]; then
  if [ -n "$bulk_advisory_warning" ]; then
    printf '%s\n' "$bulk_advisory_warning" >&2
  fi
  printf '%s\n' "$decision_json"
  exit 0
fi

printf 'Run Epic Delegated Gate\n'
printf 'Decision: %s\n' "$(printf '%s\n' "$decision_json" | jq -r '.decision')"
printf 'Merge permitted: %s\n' "$(printf '%s\n' "$decision_json" | jq -r '.mergePermitted')"
printf 'Next action: %s\n' "$(printf '%s\n' "$decision_json" | jq -r '.nextAction')"
printf 'Read-only: %s\n' "$(printf '%s\n' "$decision_json" | jq -r '.readOnlyGuarantee')"
printf 'Reasons:\n'
printf '%s\n' "$decision_json" | jq -r '.reasons[]? | "- " + .'
if [ -n "$bulk_advisory_warning" ]; then
  printf '%s\n' "$bulk_advisory_warning" >&2
fi
