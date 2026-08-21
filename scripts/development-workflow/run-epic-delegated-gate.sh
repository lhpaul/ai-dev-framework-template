#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-epic-delegated-gate.sh --input <file> [--policy <file>] [--repo-root <path>] [--product-repo <name>] [--json]
  ./scripts/development-workflow/run-epic-delegated-gate.sh verify-security-advisory-decisions --input <file>

Evaluates whether a delegated /run-epic candidate PR may proceed to the
repository merge protocol. The gate is read-only: it does not run reviewers,
poll CI, edit labels, update trackers, create comments, merge PRs, close
issues, or delete branches.

--input <file> expects the evidence schema below. This is a DIFFERENT schema
than run-epic-risk-classifier.sh's --pr/--input/--json shape -- do not feed
that script's output directly into this one's --input. Nest its result under
a top-level "risk" key instead (see the worked example). Feeding the wrong
shape in does not always fail loudly: some required fields being entirely
absent reads as an "evidence_schema_mismatch" reason (see below); assemble
each evidence file to its own documented shape.

Minimal worked example. Only .pr.number, .pr.headRefName, and .pr.baseRefName
are hard-required (the gate refuses to evaluate without them); every other key
is optional and defaults per the rules noted inline below:

  {
    "policy": {
      "delegateReview": true,
      "mayMerge": true,
      "mayStartBacklog": true
    },
    "item": {
      "number": 918,
      "status": "In Development"
    },
    "pr": {
      "number": 42,
      "headRefName": "fix/42-example",
      "baseRefName": "develop",
      "headSha": "<40-char-sha>",
      "isDraft": false,
      "mergeStateStatus": "CLEAN",
      "mergeable": "MERGEABLE",
      "labels": ["ready-for-human-review", "ready-for-regression"],
      "unresolvedBlockingThreads": 0,
      "auditDispositionPresent": true
    },
    "reviewer": {
      "status": "clean",
      "blockingCount": 0
    },
    "risk": {
      "mergePermitted": true,
      "blockers": []
    },
    "statusChecks": [
      {"name": "ci", "status": "COMPLETED", "conclusion": "SUCCESS"}
    ]
  }

.pr.mergeable follows GitHub's mergeable enum (e.g. MERGEABLE, CONFLICTING,
UNKNOWN). Omit the field entirely when you don't have this data -- do not
default it to "" (an empty string is treated the same as omitted, never as a
"not mergeable" verdict).

.pr.inScope is meaningful only when checking against a resolved /run-epic
scope; omit it entirely for /run-item or /run-items evidence -- the gate skips
the scope check when the field is absent rather than defaulting to
out-of-scope.

.policy being missing or not an object, or .statusChecks being missing, null,
or not an array (as opposed to present as an array, even an empty one),
cannot be told apart from a genuine denial or a genuine "no CI has run"
state -- the gate reports an "evidence_schema_mismatch: ..." reason naming
exactly which required shape is absent instead of guessing. This
.statusChecks check does not apply when ciPolicy/ci_policy resolves to
"none" (no CI is configured for this repository/product) -- CI-disabled
evidence is never expected to carry .statusChecks at all, so its absence is
not a schema mismatch in that case. Treat the evidence_schema_mismatch
reason as an instruction to fix the evidence file, not as a policy or CI
verdict.

When --repo-root and --product-repo are supplied (or productRepo.name is present
in the evidence file), workflow_hub product repository ci_policy is loaded from
the resolver and applied when the evidence file omits ciPolicy/ci_policy.

verify-security-advisory-decisions runs only
github_verified_security_advisory_decisions against
.securityAdvisoryDecisionEvents[] in the given evidence file and prints the
resulting verified-decision array as JSON, without evaluating the rest of
the gate. Lets Protocol 93's disposition step reuse the exact same
verification logic Gate 5 applies.
EOF
}

command=""
case "${1:-}" in
  verify-security-advisory-decisions)
    command="$1"
    shift
    ;;
esac

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
    if ! fetched="$(gh_api_bounded "$endpoint" 2>/dev/null)"; then
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
    if ! permission_response="$(gh_api_bounded "repos/${repo}/collaborators/${authorized_by}/permission" 2>/dev/null)"; then
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

# github_verified_security_advisory_decisions is structurally parallel to
# github_verified_authorization_events above, but verifies a *set* of
# candidate decision comments against a *set* of tracked
# .securityAdvisories[] findings (rather than a single authorization
# comment against one expected text), because a PR can carry multiple
# security-sensitive findings pending independent human decisions. For each
# candidate event, fetches the comment, then checks its body against every
# tracked finding's expected decision-comment template (BR6/AC11): author
# must be a human ("User") with admin or write repository permission (not
# admin-only -- a security-advisory accept/reject is not an admin merge
# override), the comment must target this exact PR
# (mirrors github_verified_authorization_events's targetPullRequest check
# at the same site -- an exact-text match alone does not bind the comment
# to the current PR), and the comment's createdAt must not be earlier than
# the matching finding's firstTrackedAt (BR6's "current head commit"
# temporal boundary -- see Stage 2 of the implementation plan; a comment
# authored before the finding was ever tracked cannot be a genuine decision
# about it). Output: one verified-decision object per resolved event,
# {findingId, decision, decider, decidedAt, rationale, sourceEventId,
# sourceEventType} -- ready to feed into
# `security-advisory-tracker.sh reconcile --decision-events`.
github_verified_security_advisory_decisions() {
  local state="$1"
  local candidates repo pr_number head_sha advisories_json
  candidates="$(printf '%s\n' "$state" | jq -c '
    def trim_text($value): ($value // "" | tostring | gsub("^\\s+|\\s+$"; ""));
    def event_id($event): trim_text($event.databaseId // $event.database_id // $event.commentId // $event.comment_id // $event.reviewId // $event.review_id // $event.id);
    def event_kind($event): trim_text($event.type // $event.eventType // $event.event_type);
    {
      repo: trim_text(.repository // .githubRepo // .github_repo // .repo // .productRepo.githubRepo // .productRepo.github_repo),
      prNumber: (.pr.number // null),
      headSha: ((.pr.headSha // .pr.head_sha // .pr.headRefOid // "") | tostring),
      events: ((.securityAdvisoryDecisionEvents // []) | map({id: event_id(.), type: event_kind(.)})),
      advisories: ((.securityAdvisories // []) | map({id: trim_text(.id), firstTrackedAt: trim_text(.firstTrackedAt)}) | map(select((.id | length) > 0)))
    }
  ' 2>/dev/null)" || {
    printf '[]\n'
    return 0
  }
  repo="$(printf '%s\n' "$candidates" | jq -r '.repo // ""')"
  pr_number="$(printf '%s\n' "$candidates" | jq -r '.prNumber // ""')"
  head_sha="$(printf '%s\n' "$candidates" | jq -r '.headSha // ""')"
  advisories_json="$(printf '%s\n' "$candidates" | jq -c '.advisories // []')"

  if [ -z "$repo" ]; then
    repo="$(repo_slug 2>/dev/null || true)"
  fi
  if ! workflow_is_valid_github_repo_slug "$repo"; then
    printf '[]\n'
    return 0
  fi
  if ! [[ "$pr_number" =~ ^[0-9]+$ && "$head_sha" =~ ^[0-9a-f]{40}$ ]]; then
    printf '[]\n'
    return 0
  fi
  if [ "$(printf '%s\n' "$advisories_json" | jq 'length')" -eq 0 ]; then
    printf '[]\n'
    return 0
  fi

  local verified='[]'
  local event id type endpoint fetched normalized permission_response author_permission matched normalized_item
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
    if ! fetched="$(gh_api_bounded "$endpoint" 2>/dev/null)"; then
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
        body: (.body // "" | gsub("^\\s+|\\s+$"; "")),
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
    if ! matched="$(printf '%s\n' "$normalized" | jq -c --argjson advisories "$advisories_json" --arg pr "$pr_number" --arg head "$head_sha" '
      (.body // "") as $body |
      [
        $advisories[] | . as $entry |
        (("I record a human decision for security-sensitive advisory finding " + $entry.id + " on PR #" + $pr + " at head " + $head + ": ") ) as $prefix |
        (
          if ($body | startswith($prefix + "accept — ")) then
            {findingId: $entry.id, decision: "human-accepted", rationale: $body[($prefix + "accept — " | length):], firstTrackedAt: $entry.firstTrackedAt}
          elif ($body | startswith($prefix + "reject — ")) then
            {findingId: $entry.id, decision: "human-rejected", rationale: $body[($prefix + "reject — " | length):], firstTrackedAt: $entry.firstTrackedAt}
          else null end
        )
      ] | map(select(. != null and ((.rationale // "") | length) > 0)) | (.[0] // null)
    ' 2>/dev/null)"; then
      continue
    fi
    if [ -z "$matched" ] || [ "$matched" = "null" ]; then
      continue
    fi
    if ! permission_response="$(gh_api_bounded "repos/${repo}/collaborators/$(printf '%s\n' "$normalized" | jq -r '.author')/permission" 2>/dev/null)"; then
      permission_response=""
    fi
    if ! author_permission="$(printf '%s\n' "$permission_response" | jq -r '.permission // ""' 2>/dev/null)"; then
      author_permission=""
    fi
    # The firstTrackedAt temporal boundary is only meaningful when both
    # timestamps are actual ISO-8601 UTC "Z" values: a lexical ">="
    # comparison against an empty firstTrackedAt (a finding whose entry
    # omitted or blanked the field) would be vacuously true for any
    # non-empty createdAt, silently disabling the BR6 boundary entirely
    # instead of rejecting the candidate for lacking a usable timestamp to
    # compare against. Requiring both to match the fixed-width UTC format
    # also keeps the lexical comparison itself valid -- it is only
    # guaranteed correct for identical UTC "Z"-suffixed formats.
    if printf '%s\n' "$normalized" | jq -e \
      --argjson matched "$matched" \
      --arg permission "$author_permission" \
      '((.authorType // "") == "User")
       and (($permission) as $p | ($p == "admin" or $p == "write"))
       and (.targetPullRequest == true)
       and (($matched.firstTrackedAt // "") | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
       and ((.createdAt // "") | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
       and ((.createdAt // "") >= ($matched.firstTrackedAt // ""))' >/dev/null; then
      # sourceEventType/sourceEventId reflect the raw candidate event's
      # {id, type} shape (the type as given on .securityAdvisoryDecisionEvents[],
      # not the normalized/lower-cased fetch-endpoint type) so they can be
      # carried straight back through security-advisory-tracker.sh's
      # --decision-events contract unchanged.
      normalized_item="$(printf '%s\n' "$normalized" | jq -c --argjson matched "$matched" --arg sourceType "$type" '{
        findingId: $matched.findingId,
        decision: $matched.decision,
        decider: .author,
        decidedAt: .createdAt,
        rationale: $matched.rationale,
        sourceEventId: .id,
        sourceEventType: $sourceType
      }' 2>/dev/null)" || continue
      verified="$(jq -c --argjson item "$normalized_item" '. + [$item]' <<< "$verified")"
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
  if ! comments="$(gh_api_bounded --paginate --slurp "repos/${repo}/issues/${pr_number}/comments?per_page=100" 2>/dev/null)"; then
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

github_verified_security_advisory_fixes() {
  local state_json="$1"
  local repo_root="$2"
  local rows id entry_head fix_commit pr_head fix_oid head_oid verified

  rows="$(printf '%s\n' "$state_json" | jq -r '
    (.pr.headSha // .pr.head_sha // .pr.headRefOid // "" | tostring) as $prHead |
    (.securityAdvisories // [])
    | map(select((.status // "") == "fixed"))
    | .[]
    | [
        (.id // ""),
        (.headSha // .head_sha // ""),
        (.fixCommit // ""),
        $prHead
      ]
    | @tsv
  ' 2>/dev/null)" || {
    printf '[]\n'
    return 0
  }

  verified="[]"
  while IFS=$'\t' read -r id entry_head fix_commit pr_head; do
    [ -n "$id" ] || continue
    [ -n "$entry_head" ] || continue
    [ "$entry_head" = "$pr_head" ] || continue
    case "$fix_commit" in
      ''|*[!0-9a-fA-F]*) continue ;;
    esac
    if [ "${#fix_commit}" -lt 7 ] || [ "${#fix_commit}" -gt 40 ]; then
      continue
    fi
    if ! fix_oid="$(git -C "$repo_root" rev-parse --verify "${fix_commit}^{commit}" 2>/dev/null)"; then
      continue
    fi
    if ! head_oid="$(git -C "$repo_root" rev-parse --verify "${pr_head}^{commit}" 2>/dev/null)"; then
      continue
    fi
    if [ "$fix_oid" != "$head_oid" ]; then
      continue
    fi
    verified="$(printf '%s\n' "$verified" | jq --arg id "$id" '. + [$id]')"
  done <<< "$rows"

  printf '%s\n' "$verified"
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

if [ "$command" = "verify-security-advisory-decisions" ]; then
  github_verified_security_advisory_decisions "$state_json"
  exit 0
fi

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
  def valid_positive_int($value):
    if ($value | type) != "number" then false
    else ($value == ($value | floor)) and ($value > 0)
    end;
  def valid_nonblank_string($value):
    if ($value | type) != "string" then false
    else (trim_text($value) | length) > 0
    end;
  (if (.pr | type) != "object" then ["pr"]
   else
     [
       (if (valid_positive_int(.pr.number) | not) then "pr.number" else empty end),
       (if (valid_nonblank_string(.pr.headRefName) | not) then "pr.headRefName" else empty end),
       (if (valid_nonblank_string(.pr.baseRefName) | not) then "pr.baseRefName" else empty end)
     ]
   end) | join(", ")
' 2>/dev/null)" || error_exit "failed to validate evidence .pr object (jq parse error)"

if [ -n "$pr_identity_gaps" ]; then
  error_exit "evidence file's .pr object is missing required identity field(s): ${pr_identity_gaps}. A missing or malformed PR identity field (pr.number must be a positive integer; pr.headRefName/pr.baseRefName must be non-blank strings) cannot be distinguished from a genuine blocker, so this gate refuses to evaluate reasons against incomplete input instead of defaulting every unpopulated field to its worst-case interpretation. Populate .pr.number, .pr.headRefName, and .pr.baseRefName from a live PR read before calling this gate."
fi

# .pr.inScope is optional (see the scope short-circuit below), but when
# present it must be a literal boolean. A non-boolean value (null, a string
# such as "false", a number, or an object) is caller-side evidence-assembly
# noise, not a real scope determination -- silently coercing it via jq's `//`
# truthiness would (depending on the value) either wrongly skip the scope
# check or wrongly trigger the not_applicable short-circuit for a PR whose
# scope was never actually resolved to false.
if printf '%s\n' "$state_json" | jq -e '(.pr | type) == "object" and (.pr | has("inScope")) and ((.pr.inScope | type) != "boolean")' >/dev/null 2>&1; then
  pr_scope_type="$(printf '%s\n' "$state_json" | jq -r '.pr.inScope | type' 2>/dev/null)"
  error_exit "evidence file's .pr.inScope field is present but not a boolean (got type: ${pr_scope_type:-unknown}). Omit .pr.inScope entirely when there is no resolved /run-epic scope to check the candidate PR against, or set it to the literal boolean true or false."
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
verified_security_advisory_decisions="$(github_verified_security_advisory_decisions "$state_json")"
state_json="$(printf '%s\n' "$state_json" | jq --argjson decisions "$verified_security_advisory_decisions" '.githubVerifiedSecurityAdvisoryDecisions = $decisions' 2>/dev/null)" || error_exit "failed to attach verified security advisory decisions"
verified_security_advisory_fixes="$(github_verified_security_advisory_fixes "$state_json" "$effective_root")"
state_json="$(printf '%s\n' "$state_json" | jq --argjson fixes "$verified_security_advisory_fixes" '.githubVerifiedSecurityAdvisoryFixes = $fixes' 2>/dev/null)" || error_exit "failed to attach verified security advisory fixes"

decision_json="$(printf '%s\n' "$state_json" | jq '
  def policy: if (.policy | type) == "object" then .policy else {} end;
  def policy_object_present: (.policy | type) == "object";
  def ci_policy: (.ciPolicy // .ci_policy // "required");
  # A key-existence check alone (`has("statusChecks")`) is not sufficient: it
  # returns true for `.statusChecks: null`, an object, or a scalar, none of
  # which are the array `ci_status_checks` below actually expects. `null`
  # would silently default to `[]` via `// []` (reported as the generic
  # "required CI state is missing" rather than a schema mismatch); an object
  # would iterate its *values* as if they were individual check entries
  # (jq map/.[] accept objects), so a single well-formed-looking check
  # value nested one level too deep could silently read as CI having passed
  # -- exactly the "malformed input rendered as a substantive verdict"
  # failure class this evidence_schema_mismatch reason exists to prevent; a
  # scalar would abort the whole jq program with an uncaught type error. This
  # predicate instead requires `.statusChecks` to literally be an array
  # (present-but-empty `[]` still counts, matching existing behavior). It
  # also requires every array member to itself be an object: a string or
  # number member reaches the reviewer_check_key field accessors (`.name`,
  # `.context`, ...) and aborts the whole jq program the same way a
  # non-array top-level value did; a `null` member does not crash but
  # silently reads as an unnamed, all-fields-absent check that reports a
  # generic CI failure instead of the more legible schema-mismatch reason.
  def status_checks_key_present:
    ((.statusChecks // null) | type) == "array" and
    ((.statusChecks // []) | all(type == "object"));
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
  # BR8/BR9: this is part of the normal reasons cascade of the gate (the
  # shared "else" block below, entered whenever .pr.inScope is absent or true), not
  # a new short-circuit -- so it evaluates on every /run-item, /run-items,
  # and /run-epic invocation surface identically, with no additional
  # scope-wiring required. BR4: this does not read, write, or call any of
  # the checkpoint_list / pending_checkpoints / checkpoint_reason /
  # invalid_checkpoint_states functions above -- it is a fully independent
  # path using its own reason string and its own
  # security-advisory-decision-required label reference (see Protocol 93).
  def security_advisory_entries:
    if ((.securityAdvisories // null) | type) == "array" then .securityAdvisories else [] end;
  def verified_security_advisory_decisions:
    if ((.githubVerifiedSecurityAdvisoryDecisions // null) | type) == "array" then .githubVerifiedSecurityAdvisoryDecisions else [] end;
  def verified_security_advisory_fixes:
    if ((.githubVerifiedSecurityAdvisoryFixes // null) | type) == "array" then .githubVerifiedSecurityAdvisoryFixes else [] end;
  # BR5: the status of a security-sensitive finding is treated as resolved
  # here only via (a) a matching verified human decision in $decisions (the
  # BR6-verified output of github_verified_security_advisory_decisions,
  # re-derived fresh on every gate call -- mirroring the existing
  # reviewer-access-bypass pattern, which never trusts a persisted
  # "authorized" flag either), or (b) status == "fixed" together with a valid
  # fixCommit already recorded on the entry for the current PR head. Every other status
  # value -- including an unrecognized string, or a "human-accepted" /
  # "human-rejected" value that is not backed by a matching verified
  # decision on THIS call, or a "fixed" entry missing fixCommit -- resolves
  # to "pending" here, unconditionally. This intentionally does not trust an
  # already-"human-accepted"/"human-rejected" status value on the entry by
  # itself: nothing about that string, on its own, proves it went through
  # BR6 verification, so trusting it directly would let a buggy or
  # malicious evidence-assembly step bypass BR5 entirely. The caller must
  # re-supply the same .securityAdvisoryDecisionEvents[] candidate
  # references on every Gate 4/5 evaluation to keep an already-resolved
  # finding unblocked (see the Gate-5-evidence-assembly paragraph in
  # Protocol 91).
  # $decisions is threaded in explicitly (not read via the no-arg
  # verified_security_advisory_decisions def) because this function is
  # invoked from inside map(select(...)) below, where the implicit `.` of
  # jq is each individual security-advisory entry, not the top-level
  # evidence state -- a no-arg def reading `.githubVerifiedSecurityAdvisoryDecisions`
  # at that call site would silently read it off the entry object instead
  # (always null there) and every finding would appear permanently pending
  # regardless of any verified decision.
  def valid_security_advisory_fix($entry; $fixes; $headSha):
    ((($entry.headSha // $entry.head_sha // "") | tostring) == $headSha)
    and ($fixes | index($entry.id // "") != null);
  def security_advisory_effective_status($entry; $decisions; $fixes; $headSha):
    ($decisions | map(select((.findingId // "") == ($entry.id // ""))) | .[0]) as $decision |
    if ($decision != null) then $decision.decision
    elif (($entry.status // "") == "fixed" and valid_security_advisory_fix($entry; $fixes; $headSha)) then "fixed"
    else "pending"
    end;
  def pending_security_advisories($decisions):
    (verified_security_advisory_fixes) as $fixes |
    (.pr.headSha // .pr.head_sha // .pr.headRefOid // "" | tostring) as $headSha |
    security_advisory_entries | map(select(security_advisory_effective_status(.; $decisions; $fixes; $headSha) == "pending"));
  # $prNumber is threaded in explicitly for the same reason $decisions is on
  # security_advisory_effective_status above (this def is invoked from
  # inside map(...), where the implicit `.` of jq is each individual entry,
  # not the top-level evidence state that carries .pr.number). Embedding the
  # PR number in the reason text mirrors the existing named-stop contract
  # already used by the graduation_approval_required and
  # human_checkpoint_required reason strings (guardrails-enforcement.md
  # section 4, plus the REVIEW.md Named-stop contract check: every stop
  # message names the exact stop condition string, the affected work item,
  # and the concrete human action).
  def security_advisory_reason($entry; $prNumber):
    "security_sensitive_advisory_pending: finding " + ($entry.id // "unknown") +
    " (" + ($entry.category // "unknown") + " @ " + ($entry.matchedFile // "unknown") + ")" +
    " on PR #" + (($prNumber // "unknown") | tostring) +
    " requires a fixed commit or a verified human accept/reject decision at head " + ($entry.headSha // "unknown");
  def ci_status_checks:
    # Coerce defensively to [] for any non-array .statusChecks (missing,
    # null, object, or scalar), and drop any non-object array member, so
    # this helper -- called unconditionally from reviewer_access_classification
    # below, not only from the guarded reasons branch that reports
    # evidence_schema_mismatch -- can never abort the whole jq program on
    # malformed input (a string/number member would otherwise reach the
    # reviewer_check_key field accessors and crash). The schema-mismatch
    # diagnosis itself is reported separately via status_checks_key_present,
    # which remains the single source of truth for "is .statusChecks
    # well-formed" (array-typed, every member an object).
    (reviewer_check_keys) as $reviewerKeys |
    ((.statusChecks // null) | if type == "array" then . else [] end)
    | map(select(type == "object"))
    | map(. as $check | select(($reviewerKeys | index(reviewer_check_key($check)) | not)));
  def current_ci_blocker:
    if ci_policy == "none" then
      false
    else
      ci_status_checks
      | any(.[]?; (success_check | not))
    end;
  def pr_mergeable_ok:
    # A blank/whitespace-only string is treated exactly like an absent field
    # (unknown mergeable state -> not blocked), not like a real GitHub
    # mergeable-enum value. Evidence assembled by hand from a `gh pr view
    # --json` call that omitted the `mergeable` field can easily default the
    # missing key to "" (e.g. via `.mergeable // ""`) rather than leaving it
    # null; without this normalization that "" would fall through to the
    # `else` branch below and be reported as a real "not mergeable" verdict
    # for a PR GitHub actually reports as MERGEABLE -- missing input rendered
    # as a substantive verdict, the same failure class pr_identity_gaps
    # already guards against for .pr identity fields above.
    ((.pr.mergeable // .pr.mergeableState // null) |
      if . == null then null else (tostring | gsub("^\\s+|\\s+$"; "")) end) as $mergeable |
    if ($mergeable == null or $mergeable == "") then true
    else (($mergeable | ascii_downcase) | IN("mergeable", "true"))
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
  # A literal boolean check, not truthiness: the bash preflight above already
  # rejects a present non-boolean .pr.inScope before this jq program runs, but
  # this definition stays independently correct (no `// false` defaulting) so
  # it cannot mis-decide even if that upstream guard is ever bypassed.
  def scope_value_false: (.pr.inScope | type) == "boolean" and (.pr.inScope == false);

  . as $state |
  if (scope_field_present and scope_value_false) then
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
  # A .policy that is entirely absent or not an object is indistinguishable,
  # field-by-field, from an explicit denial of every individual authority flag
  # once `policy` above defaults it to {} -- exactly the same conflation
  # pr_identity_gaps already guards against for .pr identity above. Report it
  # as one named, actionable evidence_schema_mismatch reason instead of the
  # two generic authority-denial reasons below, so an operator debugging a
  # malformed evidence file (e.g. one assembled from the output of a
  # different script, such as the --json result produced by
  # run-epic-risk-classifier.sh, which has no .policy at all) is not misled
  # into concluding they lack merge
  # permission when the real problem is the input shape.
  (if (policy_object_present | not) then
     add_reason($reasons; "evidence_schema_mismatch: .policy object is missing or is not an object in the evidence file; this cannot be distinguished from an explicit denial of delegated review/merge authority, so the gate reports it distinctly instead of guessing. Supply .policy as an object with explicit delegateReview and mayMerge booleans (see --help for the evidence schema) before concluding authority is denied.")
   elif (policy.delegateReview // false) != true
   then add_reason($reasons; "delegated review authority is missing")
   else $reasons end) as $reasons |
  (if (policy_object_present | not) then
     $reasons
   elif (policy.mayMerge // false) != true
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
	   elif (status_checks_key_present | not)
	   then add_reason($reasons; "evidence_schema_mismatch: .statusChecks is missing, null, or not an array in the evidence file; an absent or malformed value cannot be distinguished from a genuine \"no CI has run\" state, so the gate reports it distinctly instead of guessing. Populate .statusChecks as an array (even an empty one) built from a live PR read -- see --help for the evidence schema -- rather than substituting the output of a different script (e.g. the result produced by run-epic-risk-classifier.sh belongs nested under a top-level \"risk\" key, not here).")
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
  (verified_security_advisory_decisions) as $verifiedSecurityAdvisoryDecisions |
  (pending_security_advisories($verifiedSecurityAdvisoryDecisions)) as $pendingSecurityAdvisories |
  (.pr.number) as $prNumberForSecurityAdvisories |
  (if ($pendingSecurityAdvisories | length) > 0
   then $reasons + ($pendingSecurityAdvisories | map(security_advisory_reason(.; $prNumberForSecurityAdvisories)))
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
      elif ($reasons | any(test("authority|risk gate|needs-setup|Backlog|human_checkpoint_required|human-checkpoint|graduation_approval_required|security_sensitive_advisory_pending|evidence_schema_mismatch"))) then "human_required"
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
      elif ($reasons | any(test("security_sensitive_advisory_pending"))) then "record a fixed commit or obtain a verified human accept/reject decision for each pending security-sensitive advisory finding (never a delegated-agent-recorded acceptance/rejection), then rerun this gate"
      elif ($reasons | any(test("evidence_schema_mismatch"))) then "fix the evidence file to match the delegated-gate schema (see --help) before concluding this is a denied authority or a real missing-CI-state verdict -- an absent or malformed required field cannot be distinguished from a genuine blocker, so verify the JSON shape first, then rerun this gate"
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
