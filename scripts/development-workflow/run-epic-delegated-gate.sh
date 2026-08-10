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

github_authorization_event_candidates() {
  printf '%s\n' "$1" | jq -c '
    def authorization_events:
      if ((.authorizationEvents // null) | type) == "array" then .authorizationEvents
      elif ((.reviewerAccessAuthorizationEvents // null) | type) == "array" then .reviewerAccessAuthorizationEvents
      elif ((.reviewer_access_authorization_events // null) | type) == "array" then .reviewer_access_authorization_events
      elif ((.trustedAuthorizationEvents // null) | type) == "array" then .trustedAuthorizationEvents
      else [] end;
    def trim_text($value): ($value // "" | tostring | gsub("^\\s+|\\s+$"; ""));
    def authorization: (.authorization // .reviewerAccessAuthorization // .reviewer_access_authorization // {});
    def authorization_by: trim_text(authorization.authorizedBy // authorization.authorized_by);
    def authorization_at: trim_text(authorization.authorizedAt // authorization.authorized_at);
    def authorization_text: trim_text(authorization.authorizationText // authorization.authorization_text);
    def pr_head_sha: ((.pr.headSha // .pr.head_sha // .pr.headRefOid // "") | tostring);
    def event_id($event): trim_text($event.databaseId // $event.database_id // $event.commentId // $event.comment_id // $event.reviewId // $event.review_id // $event.id);
    def event_kind($event): trim_text($event.type // $event.eventType // $event.event_type);
    {
      repo: trim_text(.repository // .githubRepo // .github_repo // .repo // .productRepo.githubRepo // .productRepo.github_repo),
      prNumber: (.pr.number // null),
      headSha: pr_head_sha,
      evidenceFingerprint: (.computedEvidenceFingerprint // ""),
      authorizedBy: authorization_by,
      authorizedAt: authorization_at,
      authorizationText: authorization_text,
      events: (authorization_events | map({
        id: event_id(.),
        type: event_kind(.)
      }))
    }
  '
}

github_verified_authorization_events() {
  local state="$1"
  local candidates repo pr_number head_sha fingerprint authorized_by authorized_at authorization_text
  candidates="$(github_authorization_event_candidates "$state" 2>/dev/null)" || {
    printf '[]\n'
    return 0
  }
  repo="$(printf '%s\n' "$candidates" | jq -r '.repo // ""')"
  pr_number="$(printf '%s\n' "$candidates" | jq -r '.prNumber // ""')"
  head_sha="$(printf '%s\n' "$candidates" | jq -r '.headSha // ""')"
  fingerprint="$(printf '%s\n' "$candidates" | jq -r '.evidenceFingerprint // ""')"
  authorized_by="$(printf '%s\n' "$candidates" | jq -r '.authorizedBy // ""')"
  authorized_at="$(printf '%s\n' "$candidates" | jq -r '.authorizedAt // ""')"
  authorization_text="$(printf '%s\n' "$candidates" | jq -r '.authorizationText // ""')"

  if [ -z "$repo" ]; then
    repo="$(repo_slug 2>/dev/null || true)"
  fi
  if ! workflow_is_valid_github_repo_slug "$repo"; then
    printf '[]\n'
    return 0
  fi
  if ! [[ "$pr_number" =~ ^[0-9]+$ && "$head_sha" =~ ^[0-9a-f]{40}$ && "$fingerprint" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    printf '[]\n'
    return 0
  fi
  if ! [[ "$authorized_by" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}$ && "$authorized_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    printf '[]\n'
    return 0
  fi
  if [ -z "$authorization_text" ]; then
    printf '[]\n'
    return 0
  fi
  local expected_authorization_text="I authorize gh pr merge ${pr_number} --admin --match-head-commit ${head_sha} for PR #${pr_number} at head ${head_sha} with evidence fingerprint ${fingerprint}"
  if [ "$authorization_text" != "$expected_authorization_text" ]; then
    printf '[]\n'
    return 0
  fi

  local verified='[]'
  local event id type endpoint fetched normalized permission_response author_permission
  while IFS= read -r event; do
    [ -n "$event" ] || continue
    id="$(printf '%s\n' "$event" | jq -r '.id // ""')"
    type="$(printf '%s\n' "$event" | jq -r '.type // ""' | tr '[:upper:]' '[:lower:]')"
    if ! [[ "$id" =~ ^[0-9]+$ ]]; then
      continue
    fi
    case "$type" in
      comment|issue_comment)
        endpoint="repos/${repo}/issues/comments/${id}"
        ;;
      review|pull_request_review)
        endpoint="repos/${repo}/pulls/${pr_number}/reviews/${id}"
        ;;
      pull_request_review_comment|review_comment)
        endpoint="repos/${repo}/pulls/comments/${id}"
        ;;
      *)
        continue
        ;;
    esac
    if ! fetched="$(gh api "$endpoint" 2>/dev/null)"; then
      continue
    fi
    [ -n "$fetched" ] || continue
    if ! normalized="$(printf '%s\n' "$fetched" | jq -c --arg type "$type" --arg pr_number "$pr_number" '
      def trim_text($value): ($value // "" | tostring | gsub("^\\s+|\\s+$"; ""));
      def url_targets_pr($url; $segment):
        ($url // "" | tostring | test("/" + $segment + "/" + $pr_number + "($|[?#])"));
      {
        source: "github",
        type: $type,
        id: ((.id // "") | tostring),
        author: (.user.login // ""),
        authorType: (.user.type // ""),
        authorAssociation: (.author_association // ""),
        createdAt: (.created_at // .submitted_at // ""),
        body: (.body // ""),
        targetPullRequest: (
          if ($type | IN("comment", "issue_comment")) then url_targets_pr(.issue_url; "issues")
          elif ($type | IN("review", "pull_request_review")) then url_targets_pr(.pull_request_url; "pulls")
          elif ($type | IN("pull_request_review_comment", "review_comment")) then url_targets_pr(.pull_request_url; "pulls")
          else false end
        )
      }
    ' 2>/dev/null)"; then
      continue
    fi
    [ -n "$normalized" ] || continue
    if ! permission_response="$(gh api "repos/${repo}/collaborators/${authorized_by}/permission" 2>/dev/null)"; then
      permission_response=""
    fi
    if ! author_permission="$(printf '%s\n' "$permission_response" | jq -r '.permission // ""' 2>/dev/null)"; then
      author_permission=""
    fi
    if ! normalized="$(printf '%s\n' "$normalized" | jq -c --arg permission "$author_permission" '.authorPermission = $permission' 2>/dev/null)"; then
      continue
    fi
    [ -n "$normalized" ] || continue
    if printf '%s\n' "$normalized" | jq -e \
      --arg author "$authorized_by" \
      --arg created "$authorized_at" \
      --arg expected "$expected_authorization_text" \
      '.author == $author
       and .createdAt == $created
       and ((.authorType // "") == "User")
       and ((.authorPermission // "") == "admin")
       and (.targetPullRequest == true)
       and ((.body | gsub("^\\s+|\\s+$"; "")) == $expected)' >/dev/null; then
      verified="$(jq -c --argjson item "$normalized" '. + [$item]' <<< "$verified")"
    fi
  done < <(printf '%s\n' "$candidates" | jq -c '.events[]?')

  printf '%s\n' "$verified"
}

github_verified_bypass_audit() {
  local state="$1"
  local audit_candidate repo pr_number head_sha fingerprint
  audit_candidate="$(printf '%s\n' "$state" | jq -c '
    def trim_text($value): ($value // "" | tostring | gsub("^\\s+|\\s+$"; ""));
    def bypass_audit: (.bypassAudit // .bypass_audit // {});
    {
      repo: trim_text(.repository // .githubRepo // .github_repo // .repo // .productRepo.githubRepo // .productRepo.github_repo),
      prNumber: (.pr.number // null),
      headSha: ((.pr.headSha // .pr.head_sha // .pr.headRefOid // "") | tostring),
      evidenceFingerprint: (.computedEvidenceFingerprint // ""),
      state: trim_text(bypass_audit.state),
      commentId: trim_text(bypass_audit.commentId // bypass_audit.comment_id)
    }
  ' 2>/dev/null)" || {
    printf '{"present":false}\n'
    return 0
  }
  repo="$(printf '%s\n' "$audit_candidate" | jq -r '.repo // ""')"
  pr_number="$(printf '%s\n' "$audit_candidate" | jq -r '.prNumber // ""')"
  head_sha="$(printf '%s\n' "$audit_candidate" | jq -r '.headSha // ""')"
  fingerprint="$(printf '%s\n' "$audit_candidate" | jq -r '.evidenceFingerprint // ""')"
  if [ -z "$repo" ]; then
    repo="$(repo_slug 2>/dev/null || true)"
  fi
  if ! workflow_is_valid_github_repo_slug "$repo"; then
    printf '{"present":false}\n'
    return 0
  fi
  if ! [[ "$pr_number" =~ ^[0-9]+$ && "$head_sha" =~ ^[0-9a-f]{40}$ && "$fingerprint" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    printf '{"present":false}\n'
    return 0
  fi

  local comments
  if ! comments="$(gh api --paginate --slurp "repos/${repo}/issues/${pr_number}/comments?per_page=100" 2>/dev/null)"; then
    comments=""
  fi
  if [ -z "$comments" ]; then
    printf '{"present":false}\n'
    return 0
  fi
  printf '%s\n' "$comments" | jq -c \
    --arg marker '<!-- reviewer-access-bypass -->' \
    --arg state 'authorized_pending_attempt' \
    --arg pr "#${pr_number}" \
    --arg head "$head_sha" \
    --arg fp "$fingerprint" \
    --arg action "gh pr merge ${pr_number} --admin --match-head-commit ${head_sha}" '
    def audit_lines:
      (.body // "" | split("\n") | map(gsub("\r$"; "")));
    def audit_section:
      audit_lines as $lines
      | ($lines | index("## Reviewer Access Bypass Audit")) as $heading
      | if $heading == null then {}
        else ($heading + 2) as $start
        | {
            state: ($lines[$start] // ""),
            pr: ($lines[$start + 4] // ""),
            head: ($lines[$start + 5] // ""),
            fingerprint: ($lines[$start + 6] // ""),
            action: ($lines[$start + 7] // ""),
            terminator: ($lines[$start + 8] // "")
          }
        end;
    [.[][]? | select((.body // "") | contains($marker)) | audit_section as $audit | {
      present: true,
      commentId: ((.id // "") | tostring),
      state: $state,
      evidenceFingerprint: $fp,
      body: (.body // "")
    } | select(
      ($audit.state == "- State: " + $state)
      and ($audit.pr == "- PR: " + $pr)
      and ($audit.head == "- Head SHA: `" + $head + "`")
      and ($audit.fingerprint == "- Evidence fingerprint: `" + $fp + "`")
      and ($audit.action == "- Proposed action: `" + $action + "`")
      and ($audit.terminator == "")
    )][0] // {present:false}
  ' 2>/dev/null || printf '{"present":false}\n'
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

# Refuse to evaluate reasons against an incompletely populated .pr object. A
# caller-side evidence-assembly failure that leaves .pr.number/.headRefName/
# .baseRefName unpopulated is indistinguishable, field-by-field, from a real
# blocker once the reasons cascade below applies its per-field worst-case
# defaults — that conflation is what produces a misleading pile of false
# blockers instead of a clear, actionable error. These three fields are the
# minimal PR identity every live `gh pr view` read always populates, so their
# absence is a reliable, low-false-positive signal of missing/failed evidence
# assembly rather than a legitimate "field intentionally omitted" case (unlike
# optional fields such as labels, mergeStateStatus, or auditDispositionPresent,
# which existing callers legitimately omit and expect worst-case defaulting
# for).
pr_identity_gaps="$(printf '%s\n' "$state_json" | jq -r '
  def trim_text($value): ($value // "" | tostring | gsub("^\\s+|\\s+$"; ""));
  (if (.pr | type) != "object" then ["pr"]
   else
     [
       (if (.pr.number == null) then "pr.number" else empty end),
       (if (trim_text(.pr.headRefName) | length) == 0 then "pr.headRefName" else empty end),
       (if (trim_text(.pr.baseRefName) | length) == 0 then "pr.baseRefName" else empty end)
     ]
   end) | join(", ")
' 2>/dev/null)" || error_exit "failed to validate evidence .pr object (jq parse error)"

if [ -n "$pr_identity_gaps" ]; then
  error_exit "evidence file's .pr object is missing required identity field(s): ${pr_identity_gaps}. A missing PR identity field cannot be distinguished from a genuine blocker, so this gate refuses to evaluate reasons against incomplete input instead of defaulting every unpopulated field to its worst-case interpretation. Populate .pr.number, .pr.headRefName, and .pr.baseRefName from a live PR read before calling this gate."
fi

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
verified_authorization_events="$(github_verified_authorization_events "$state_json")"
state_json="$(printf '%s\n' "$state_json" | jq --argjson events "$verified_authorization_events" '.githubVerifiedAuthorizationEvents = $events' 2>/dev/null)" || error_exit "failed to attach verified authorization events"
verified_bypass_audit="$(github_verified_bypass_audit "$state_json")"
state_json="$(printf '%s\n' "$state_json" | jq --argjson audit "$verified_bypass_audit" '.githubVerifiedBypassAudit = $audit' 2>/dev/null)" || error_exit "failed to attach verified bypass audit"

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
  def checkpoint_state($cp):
    (($cp.satisfaction_state // "pending") | tostring | gsub("^\\s+|\\s+$"; "") | ascii_downcase);
  def invalid_checkpoint_states:
    checkpoint_list
    | map(select((checkpoint_state(.) | IN("pending", "satisfied", "waived")) | not));
  def checkpoint_applies($cp; $item; $prStage):
    ($item != null)
    and (($cp.item_number | tonumber) == ($item | tonumber))
    and (checkpoint_state($cp) == "pending")
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
  def reviewer_check_key($check):
    if ($check.__typename // "") == "StatusContext" then reviewer_check_name($check)
    else (($check.workflowName // $check.workflow // $check.provider // "") + "\u0000" + reviewer_check_name($check))
    end;
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
  def reviewer_check_keys:
    reviewer_checks | map(reviewer_check_key(.));
  def advisory_entries:
    if ((.advisories // null) | type) == "array" then .advisories
    elif ((.reviewer.advisories // null) | type) == "array" then .reviewer.advisories
    else [] end;
  def advisory_count:
    ((.reviewer.advisoryCount // .reviewer.advisory_count // 0) | tonumber);
  def accepted_advisory_missing_rationale($advisory):
    (($advisory.decision // $advisory.disposition // $advisory.status // "") | ascii_downcase) as $decision |
    (($advisory.rationale // $advisory.reason // $advisory.mitigation // "") | tostring | gsub("^\\s+|\\s+$"; "") | length) as $rationale_length |
    ($decision | test("accept")) and ($rationale_length == 0);
  def advisory_missing_disposition($advisory):
    (($advisory.decision // $advisory.disposition // $advisory.status // "") | ascii_downcase) as $decision |
    (($decision | IN("fixed", "accepted")) | not);
  def advisory_evidence_incomplete:
    (advisory_entries) as $advisories |
    (advisory_count > 0 and ($advisories | length) < advisory_count)
    or ($advisories | any(advisory_missing_disposition(.) or accepted_advisory_missing_rationale(.)));
  def ci_status_checks:
    (reviewer_check_keys) as $reviewerKeys |
    (.statusChecks // [])
    | map(. as $check | select(($reviewerKeys | index(reviewer_check_key($check)) | not)));
  def current_ci_blocker:
    if ci_policy == "none" then
      false
    else
      ci_status_checks
      | any(.[]?; (success_check | not))
    end;
  def pr_mergeable_ok:
    (.pr.mergeable // .pr.mergeableState // null) as $mergeable |
    if $mergeable == null then true
    else (($mergeable | tostring | ascii_downcase) | IN("mergeable", "true"))
    end;
  def access_obj: (.accessRestriction // .access_restriction // {});
  def access_obj_present:
    (access_obj | type) == "object" and ((access_obj | length) > 0);
  def access_denial_reason:
    (access_obj.reason // access_obj.providerReason // .reviewer.reason // "")
    | tostring
    | ascii_downcase;
  def access_denial_evidence:
    (access_obj.evidence // access_obj.source // "")
    | tostring
    | ascii_downcase;
  def access_denial_verified:
    (
      (access_denial_reason | test("^(forbidden|unauthorized|access[_ -]?restricted|http[ _-]?403|403)$"))
      or
      (access_denial_evidence | test("http[[:space:]]*403|\\b403\\b[[:space:]:-]*(forbidden|resource not accessible)|resource not accessible by integration|permission denied|access denied|access[_ -]?restricted|unauthorized"))
    );
  def remediation_ready:
    (access_obj.remediationAttempted // access_obj.remediation_attempted // false) == true
    and (access_obj.cannotUnblockInTime // access_obj.cannot_unblock_in_time // false) == true
    and ((access_obj.bypassReason // access_obj.bypass_reason // "") | tostring | length) > 0;
  def authorization: (.authorization // .reviewerAccessAuthorization // .reviewer_access_authorization // {});
  def trim_text($value): ($value // "" | tostring | gsub("^\\s+|\\s+$"; ""));
  def authorization_by: trim_text(authorization.authorizedBy // authorization.authorized_by);
  def authorization_at: trim_text(authorization.authorizedAt // authorization.authorized_at);
  def authorization_text: trim_text(authorization.authorizationText // authorization.authorization_text);
  def named_authorization_present:
    (authorization_by | test("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$"))
    and (authorization_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    and (authorization_text | length) > 0;
  def pr_head_sha: ((.pr.headSha // .pr.head_sha // .pr.headRefOid // "") | tostring);
  def valid_pr_head_sha: (pr_head_sha | test("^[0-9a-f]{40}$"));
  def authorization_events:
    if ((.githubVerifiedAuthorizationEvents // null) | type) == "array" then .githubVerifiedAuthorizationEvents
    else [] end;
  def event_author($event):
    trim_text(
      if (($event.author // null) | type) == "object" then
        ($event.author.login // $event.author.name // "")
      else
        ($event.author // $event.login // $event.authorLogin // $event.author_login)
      end
    );
  def trusted_author($event):
    (trim_text($event.authorType // $event.author_type) == "User")
    and (trim_text($event.authorPermission // $event.author_permission) == "admin");
  def target_pr_verified($event):
    ($event.targetPullRequest // $event.target_pull_request // false) == true;
  def trusted_authorization_event_present:
    (authorization_by) as $authorization_by |
    (authorization_at) as $authorization_at |
    (authorization_text) as $authorization_text |
    authorization_events
    | any(. as $event |
        ((trim_text($event.source // $event.provider) | ascii_downcase) == "github")
        and ((trim_text($event.type // $event.eventType // $event.event_type) | ascii_downcase)
          | IN("comment", "issue_comment", "pull_request_review", "review", "pull_request_review_comment", "review_comment"))
        and (event_author($event) == $authorization_by)
        and trusted_author($event)
        and target_pr_verified($event)
        and (trim_text($event.createdAt // $event.created_at // $event.submittedAt // $event.submitted_at) == $authorization_at)
        and (trim_text($event.body // $event.text // $event.authorizationText // $event.authorization_text) == $authorization_text)
      );
  def bypass_audit: (.githubVerifiedBypassAudit // {});
  def reviewer_blocks:
    ((.reviewer.blockingCount // .reviewer.blocking_count // 0) | tonumber) > 0
    or ((.reviewer.status // "") | test("needs_fixes|failed|blocked"));
  def reviewer_access_classification:
    (non_green_reviewer_checks) as $blockedChecks |
    (.computedEvidenceFingerprint // "") as $fingerprint |
    if current_ci_blocker then "ci_blocker"
    elif reviewer_blocks then "review_blocker"
    elif (($blockedChecks | length) == 0) and access_obj_present then "insufficient_evidence"
    elif (($blockedChecks | length) == 0) then "not_applicable"
    elif (access_denial_verified | not) then "insufficient_evidence"
    elif (remediation_ready | not) then "access_restricted"
    elif (valid_pr_head_sha | not) then "insufficient_evidence"
    elif ((authorization.pullRequest // authorization.pull_request // null) == null) then "authorization_required"
    elif (named_authorization_present | not) then "authorization_required"
    elif (((authorization.pullRequest // authorization.pull_request) | tostring) != ((.pr.number // "") | tostring)
       or ((authorization.headSha // authorization.head_sha // "") != pr_head_sha)
       or ((authorization.evidenceFingerprint // authorization.evidence_fingerprint // "") != $fingerprint)) then "authorization_stale"
    elif (trusted_authorization_event_present | not) then "authorization_required"
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
        elif $classification == "exceptional_bypass_authorized" then "execute exactly the named gh pr merge --admin --match-head-commit action once, then verify and update audit"
        elif $classification == "insufficient_evidence" then "refresh reviewer check and provider access-denial evidence"
        elif $classification == "ci_blocker" then "fix or complete CI before considering reviewer access restriction"
        elif $classification == "review_blocker" then "fix reviewer findings before considering reviewer access restriction"
        else "not applicable" end
      ),
      proposedAction: (if $classification == "exceptional_bypass_authorized" then "gh pr merge " + ((.pr.number // "") | tostring) + " --admin --match-head-commit " + pr_head_sha else "" end)
    };
  def add_reason($reasons; $reason): $reasons + [$reason];
  def reason_count($reasons): $reasons | length;
  def exceptional_bypass_preconditions($reasons; $classification):
    $classification == "exceptional_bypass_authorized"
    and pr_mergeable_ok
    and (($reasons | length) > 0)
    and ($reasons | all(. == "PR merge state is not CLEAN"));
  def scope_field_present: (.pr | type) == "object" and (.pr | has("inScope"));
  def scope_value_true: (.pr.inScope // false) == true;

  . as $state |
  if (scope_field_present and (scope_value_true | not)) then
  {
    decision: "not_applicable",
    mergePermitted: false,
    exceptionalAdminMergePermitted: false,
    reasons: ["candidate PR is not in the resolved run-epic scope"],
    reviewerAccess: {
      classification: "not_applicable",
      pullRequest: (.pr.number // null),
      headSha: pr_head_sha,
      evidenceFingerprint: (.computedEvidenceFingerprint // ""),
      blockedReviewerChecks: [],
      primaryAction: "not applicable",
      proposedAction: ""
    },
    nextAction: "not applicable: candidate PR is not in the resolved run-epic scope; no action is required from this gate for this PR",
    pr: {
      number: (.pr.number // null),
      headRefName: (.pr.headRefName // ""),
      baseRefName: (.pr.baseRefName // "")
    },
    policy: policy,
    readOnlyGuarantee: "No reviewer-loop runs, CI polling, label edits, tracker updates, comments, merges, issue closure, or branch deletion were performed."
  }
  else
  (
  [] as $reasons |
  (invalid_checkpoint_states) as $invalidCheckpointStates |
  (if ($invalidCheckpointStates | length) > 0
   then add_reason($reasons; "human_checkpoint_required: invalid checkpoint satisfaction_state; expected pending, satisfied, or waived")
   else $reasons end) as $reasons |
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
	   elif (ci_status_checks | length) == 0
	   then add_reason($reasons; "required CI state is missing")
	   else $reasons end) as $reasons |
	  (if (ci_policy == "none")
	   then $reasons
	   elif ((ci_status_checks | map(select(success_check | not)) | length) > 0)
	   then add_reason($reasons; "one or more required CI checks are not successful")
	   else $reasons end) as $reasons |
  (if (.pr.mergeStateStatus // "") != "CLEAN"
   then add_reason($reasons; "PR merge state is not CLEAN")
   else $reasons end) as $reasons |
  (if (pr_mergeable_ok | not)
   then add_reason($reasons; "PR is not mergeable")
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
  (if advisory_evidence_incomplete
   then add_reason($reasons; "reviewer advisories require per-finding fix or acceptance rationale")
   else $reasons end) as $reasons |
  (if (ci_policy == "none") and (risk_merge_permitted != true) and risk_ci_only_blockers
   then $reasons
   elif risk_merge_permitted != true
   then add_reason($reasons; "risk gate does not permit merge")
   else $reasons end) as $reasons |
  (if (.pr.auditDispositionPresent // false) != true
   then add_reason($reasons; "PR disposition audit is missing")
   else $reasons end) as $reasons |
  reviewer_access_classification as $reviewerAccessClassification |
  reviewer_access_summary($reviewerAccessClassification) as $reviewerAccess |
  (exceptional_bypass_preconditions($reasons; $reviewerAccessClassification)) as $exceptionalBypassPermitted |
  (reason_count($reasons)) as $count |
  {
    decision: (
      if $exceptionalBypassPermitted then "exceptional_bypass_authorized"
      elif $reviewerAccessClassification == "ci_blocker" or $reviewerAccessClassification == "review_blocker" then "fix_required"
      elif $reviewerAccessClassification == "insufficient_evidence" then "blocked"
      elif ($reviewerAccessClassification | IN("access_restricted", "authorization_required", "authorization_stale", "audit_required")) then "human_required"
      elif $count == 0 then "merge_allowed"
      elif ($reasons | any(test("reviewer blocking|CI checks|unresolved blocking|advisories"))) then "fix_required"
      elif ($reasons | any(test("authority|risk gate|needs-setup|Backlog|human_checkpoint_required|human-checkpoint|graduation_approval_required"))) then "human_required"
      else "blocked"
      end
    ),
    mergePermitted: ($count == 0 and ($reviewerAccessClassification | IN("not_applicable", "exceptional_bypass_authorized"))),
    exceptionalAdminMergePermitted: $exceptionalBypassPermitted,
    reasons: $reasons,
    reviewerAccess: $reviewerAccess,
    nextAction: (
      if $exceptionalBypassPermitted then "execute exactly the named admin merge once, then verify merge state, cleanup, tracker reconciliation, and audit update"
      elif ($reviewerAccessClassification | IN("access_restricted", "authorization_required", "authorization_stale", "audit_required", "insufficient_evidence")) then $reviewerAccess.primaryAction
      elif $count == 0 then "record merge evidence and use the repository merge protocol"
      elif ($reasons | any(test("reviewer blocking|CI checks|unresolved blocking|advisories"))) then "remove readiness labels, fix, rerun validation, reviewer loop, CI loop, and this gate"
      elif ($reasons | any(test("human_checkpoint_required|human-checkpoint"))) then "stop for the named human checkpoint action, record satisfied or waived evidence, sync labels, and rerun this gate"
      elif ($reasons | any(test("graduation_approval_required"))) then "stop for explicit graduation approval via /graduate-development before mutating"
      elif ($reasons | any(test("authority|risk gate|needs-setup|Backlog"))) then "stop for human authority or setup before mutating"
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
  )
  end
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
printf 'Exceptional admin merge permitted: %s\n' "$(printf '%s\n' "$decision_json" | jq -r '.exceptionalAdminMergePermitted')"
printf 'Reviewer access classification: %s\n' "$(printf '%s\n' "$decision_json" | jq -r '.reviewerAccess.classification')"
printf 'Reviewer access proposed action: %s\n' "$(printf '%s\n' "$decision_json" | jq -r '.reviewerAccess.proposedAction')"
printf 'Next action: %s\n' "$(printf '%s\n' "$decision_json" | jq -r '.nextAction')"
printf 'Read-only: %s\n' "$(printf '%s\n' "$decision_json" | jq -r '.readOnlyGuarantee')"
printf 'Reasons:\n'
printf '%s\n' "$decision_json" | jq -r '.reasons[]? | "- " + .'
if [ -n "$bulk_advisory_warning" ]; then
  printf '%s\n' "$bulk_advisory_warning" >&2
fi
