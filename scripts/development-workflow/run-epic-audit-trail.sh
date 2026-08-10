#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

PR_MARKER="<!-- run-epic:pr-disposition -->"
EPIC_MARKER="<!-- run-epic:epic-ledger -->"
REVIEWER_ACCESS_BYPASS_MARKER="<!-- reviewer-access-bypass -->"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-epic-audit-trail.sh render-pr-disposition --input <file>
  ./scripts/development-workflow/run-epic-audit-trail.sh apply-pr-disposition --input <file> --pr <number>
  ./scripts/development-workflow/run-epic-audit-trail.sh render-epic-ledger --input <file>
  ./scripts/development-workflow/run-epic-audit-trail.sh apply-epic-ledger --input <file> --epic <number>
  ./scripts/development-workflow/run-epic-audit-trail.sh render-reviewer-access-bypass --input <file>
  ./scripts/development-workflow/run-epic-audit-trail.sh apply-reviewer-access-bypass --input <file> --pr <number>

Renders or applies stable /run-epic audit comments. Apply mode updates an
existing marker comment or creates one when no marker exists.
EOF
}

command="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi
input_file=""
pr_number=""
epic_number=""

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

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0*) return 1 ;;
    *) return 0 ;;
  esac
}

load_input_json() {
  local file="$1"
  if [ ! -f "$file" ]; then
    error_exit "input file not found: $file"
  fi
  if [ ! -s "$file" ]; then
    error_exit "input file is empty: $file"
  fi
  jq -c '.' "$file" 2>/dev/null || error_exit "input file is not valid JSON: $file"
}

redact_text() {
  sed -E \
    -e 's#gh[pousr]_[A-Za-z0-9_]+#[REDACTED_TOKEN]#g' \
    -e 's#Bearer[[:space:]]+[A-Za-z0-9._=-]+#Bearer [REDACTED]#g' \
    -e 's#Authorization:[[:space:]]*[^[:space:]]+#Authorization: [REDACTED]#g' \
    -e 's#/Users/[^[:space:]|)]+#[REDACTED_LOCAL_PATH]#g' \
    -e 's#/tmp/[^[:space:]|)]+#[REDACTED_LOCAL_PATH]#g'
}

table_cell_filter='
  def cell:
    tostring
    | gsub("\\|"; "\\\\|")
    | gsub("\\r?\\n"; "<br>")
    | gsub("\\t"; " ");
'

checkpoint_stage_filter='
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
  def checkpoint_applies($cp; $item; $prStage):
    (($cp.item_number | tonumber) == ($item | tonumber))
    and ($cp.satisfaction_state // "pending") == "pending"
    and (stage_rank($cp.stage) > 0)
    and (stage_rank($cp.stage) <= stage_rank($prStage));
'

render_pr_disposition() {
  local json="$1"
  local missing
  local missing_status=0
  local rendered

  # NOTE: this function is called both directly (render-pr-disposition) and
  # via command substitution, e.g. `body="$(render_pr_disposition ...)"`
  # (apply-pr-disposition). Bash's `set -e` does not abort a function whose
  # commands run inside a context where -e is already being ignored (which a
  # nested command substitution is), so a failing `jq` call below would
  # otherwise silently produce an empty $missing and let this guard pass
  # vacuously in apply mode. Each dotted field lookup is wrapped in
  # `try ... catch null` so a wrong-typed value (e.g. .item being a string)
  # is reported as missing instead of crashing jq outright, and the exit
  # status of the jq call itself is captured explicitly via `||` (not
  # relied upon via -e propagation) so any other jq failure still aborts
  # loudly in both call contexts. See issue #1430.
  #
  # The same -e-ignored context also means a failing jq call *inside* the
  # `{ ... } | redact_text` body block below (e.g. a wrong-typed
  # .invocation_policy, .checkpoint_policy, or .verification) would not
  # abort execution either — worse, because `{ ... }` is the first stage of
  # a pipeline, bash runs it in its own subshell (pipelines run every
  # non-last stage in a subshell unless `shopt -s lastpipe` is active,
  # which this script does not set), so a shared flag variable set inside
  # that block cannot be read after the pipe: it would still show its
  # initial value once the pipe returns, silently masking the failure a
  # second way. Each of those three optional sections below therefore
  # calls `error_exit` immediately (via `|| error_exit ...`) the moment
  # its jq capture fails, instead of deferring to a flag check — `exit` is
  # not subject to -e semantics at all, so it terminates the `{ ... }`
  # subshell right there; combined with `pipefail`, that makes the whole
  # `{ ... } | redact_text` pipeline (and therefore this function, and the
  # apply-* command substitution around it) report the failure reliably in
  # both call contexts. See CodeRabbit finding on PR #1459 (issue #1430).
  missing="$(printf '%s\n' "$json" | jq -r '
    [
      ["scope_source", (try .scope_source catch null)],
      ["item.number", (try .item.number catch null)],
      ["item.title", (try .item.title catch null)],
      ["pr.number", (try .pr.number catch null)],
      ["pr.head_sha", (try .pr.head_sha catch null)],
      ["reviewer.result", (try .reviewer.result catch null)],
      ["risk.level", (try .risk.level catch null)],
      ["merge_authority", (try .merge_authority catch null)],
      ["final_decision", (try .final_decision catch null)]
    ]
    | map(select(.[1] == null or (.[1] | tostring | length == 0)) | .[0])
    | join(", ")
  ')" || missing_status=$?
  if [ "$missing_status" -ne 0 ]; then
    error_exit "failed to evaluate required PR disposition fields (jq exit ${missing_status})"
  fi
  if [ -n "$missing" ]; then
    error_exit "missing required PR disposition fields: $missing"
  fi

  {
    printf '%s\n' "$PR_MARKER"
    printf '## /run-epic PR Disposition\n\n'
    printf '%s\n' "$json" | jq -r '
      "- Scope source: " + (.scope_source | tostring),
      "- Item: #" + (.item.number | tostring) + " - " + (.item.title | tostring),
      "- PR: #" + (.pr.number | tostring),
      "- Reviewed head SHA: `" + (.pr.head_sha | tostring) + "`",
      "- Reviewer result: " + (.reviewer.result | tostring),
      "- Blocking findings: " + ((.reviewer.blocking_count // 0) | tostring),
      "- Advisory findings: " + ((.reviewer.advisory_count // 0) | tostring),
      "- Risk: " + (.risk.level | tostring),
      "- Merge authority: " + (.merge_authority | tostring),
      "- Final decision: " + (.final_decision | tostring)
    '
    printf '\n### Risk Reasons\n\n'
    printf '%s\n' "$json" | jq -r '(.risk.reasons // [])[]? | "- " + (.|tostring)'
    printf '\n### Invocation Policy\n\n'
    if [ "$(printf '%s\n' "$json" | jq 'if (.invocation_policy // null) == null then 0 else 1 end')" -eq 0 ]; then
      printf 'Not recorded.\n'
    else
      rendered="$(printf '%s\n' "$json" | jq -r '
        (.invocation_policy // {}) as $p |
        "- Original command: `" + (($p.original_command // $p.originalCommand // "") | tostring) + "`",
        "- Copy-paste equivalent: `" + (($p.copy_paste_command // $p.copyPasteCommand // "") | tostring) + "`",
        "- Confirmation: " + (($p.confirmation // $p.confirmationReason // "not recorded") | tostring)
      ')" || error_exit "failed to render invocation policy detail (jq error above)"
      printf '%s\n' "$rendered"
      printf '\n| Field | Recommended | Selected | Effective |\n'
      printf '| --- | --- | --- | --- |\n'
      rendered="$(printf '%s\n' "$json" | jq -r "$table_cell_filter"'
        (.invocation_policy // {}) as $p |
        ($p.recommended_policy // $p.recommendedPolicy // {}) as $r |
        ($p.selected_policy // $p.selectedPolicy // {}) as $s |
        ($p.effective_policy // $p.effectivePolicy // {}) as $e |
        ["mayStartBacklog", "delegateReview", "mayMerge", "maxRisk", "base"][] as $field |
        "| " + $field +
        " | " + (($r[$field] // "") | cell) +
        " | " + (($s[$field] // "") | cell) +
        " | " + (($e[$field] // "") | cell) + " |"
      ')" || error_exit "failed to render invocation policy table (jq error above)"
      printf '%s\n' "$rendered"
    fi
    printf '\n### Checkpoint Policy\n\n'
    if [ "$(printf '%s\n' "$json" | jq 'if (.checkpoint_policy // .checkpointPolicy // null) == null then 0 else 1 end')" -eq 0 ]; then
      printf 'Not recorded.\n'
    else
      rendered="$(printf '%s\n' "$json" | jq -r "$checkpoint_stage_filter"'
        (.checkpoint_policy // .checkpointPolicy // {}) as $cp |
        (.item.number) as $itemNum |
        (.pr.branch // "") as $branch |
        ((.pr.stage // "") as $stage |
          if ($branch | length) > 0 then stage_from_branch($branch)
          elif ($stage | length) > 0 then $stage
          else null end) as $prStage |
        "- Field source: " + (($cp.field_source // $cp.fieldSource // "unknown") | tostring),
        "- Pending applicable checkpoints: " + (
          [($cp.effective // $cp.effectivePolicy // [])[]
            | select(
                if $prStage == null then
                  (.satisfaction_state == "pending" and ((.item_number | tonumber) == ($itemNum | tonumber)))
                else
                  checkpoint_applies(.; ($itemNum | tostring); $prStage)
                end
              )] | length | tostring
        )
      ')" || error_exit "failed to render checkpoint policy detail (jq error above)"
      printf '%s\n' "$rendered"
      printf '\n| Item | Stage | Domain | State | Reason | Required action |\n'
      printf '| --- | --- | --- | --- | --- | --- |\n'
      rendered="$(printf '%s\n' "$json" | jq -r "$table_cell_filter $checkpoint_stage_filter"'
        (.checkpoint_policy // .checkpointPolicy // {}) as $cp |
        (.item.number) as $itemNum |
        (.pr.branch // "") as $branch |
        ((.pr.stage // "") as $stage |
          if ($branch | length) > 0 then stage_from_branch($branch)
          elif ($stage | length) > 0 then $stage
          else null end) as $prStage |
        ($cp.effective // $cp.effectivePolicy // [])[]
        | select((.item_number | tonumber) == ($itemNum | tonumber))
        | select(
            if $prStage == null then true
            else checkpoint_applies(.; ($itemNum | tostring); $prStage) or (.satisfaction_state // "pending") != "pending"
            end
          ) |
        "| #" + (.item_number | tostring) +
        " | " + ((.stage // "") | cell) +
        " | " + ((.domain // "") | cell) +
        " | " + ((.satisfaction_state // "pending") | cell) +
        " | " + ((.reason // "") | cell) +
        " | " + ((.required_human_action // "") | cell) + " |"
      ')" || error_exit "failed to render checkpoint policy table (jq error above)"
      printf '%s\n' "$rendered"
    fi
    printf '\n### Advisory Decisions\n\n'
    if [ "$(printf '%s\n' "$json" | jq '(.advisories // []) | length')" -eq 0 ]; then
      printf 'None.\n'
    else
      printf '| Source | Category | Decision | Rationale |\n'
      printf '| --- | --- | --- | --- |\n'
      printf '%s\n' "$json" | jq -r "$table_cell_filter"'
        (.advisories // [])[] |
        "| " + ((.source // "") | cell) +
        " | " + ((.category // "") | cell) +
        " | " + ((.decision // "") | cell) +
        " | " + ((.rationale // "") | cell) + " |"
      '
    fi
    printf '\n### Verification Evidence\n\n'
    rendered="$(printf '%s\n' "$json" | jq -r '
      (.verification // {}) as $v |
      "- Labels: " + (($v.labels // []) | join(", ")),
      "- CI result: " + (($v.ci_result // "unknown") | tostring),
      "- Reviewer summary present: " + (($v.reviewer_summary_present // false) | tostring),
      "- Unresolved thread count: " + (($v.unresolved_thread_count // "unknown") | tostring),
      "- PR merge state: " + (($v.merge_state // "unknown") | tostring),
      "- Issue state: " + (($v.issue_state // "unknown") | tostring),
      "- Project status: " + (($v.project_status // "unknown") | tostring)
    ')" || error_exit "failed to render verification evidence (jq error above)"
    printf '%s\n' "$rendered"
    printf '\n### Protocol Deviations\n\n'
    if [ "$(printf '%s\n' "$json" | jq '(.protocol_deviations // []) | length')" -eq 0 ]; then
      printf 'None.\n'
    else
      printf '| Action | Impact | Mitigation |\n'
      printf '| --- | --- | --- |\n'
      printf '%s\n' "$json" | jq -r "$table_cell_filter"'
        (.protocol_deviations // [])[] |
        "| " + ((.action // "") | cell) +
        " | " + ((.impact // "") | cell) +
        " | " + ((.mitigation // "") | cell) + " |"
      '
    fi
  } | redact_text
}

validate_advisories() {
  local json="$1"
  local invalid
  invalid="$(printf '%s\n' "$json" | jq -r '
    (.advisories // [])
    | map(select((.decision // "") != "fixed" and ((.rationale // "") | gsub("\\s"; "") | length == 0)))
    | length
  ' 2>/dev/null)" || error_exit "failed to validate advisory entries (jq parse error)"
  if [ -z "$invalid" ]; then
    error_exit "failed to validate advisory entries (empty result)"
  fi
  invalid="${invalid}" || error_exit "failed to validate advisory entries (invalid type)"
  if [ "$invalid" -gt 0 ]; then
    error_exit "non-fixed advisory decisions require rationale"
  fi
}

warn_per_finding_advisories() {
  local json="$1"
  local advisory_count advisories_len bulk_rationale
  advisory_count="$(printf '%s\n' "$json" | jq -r '(.reviewer.advisoryCount // .reviewer.advisory_count // 0) | tonumber' 2>/dev/null)" || error_exit "failed to read advisory count (jq parse error)"
  if [ -z "$advisory_count" ]; then
    error_exit "failed to read advisory count (empty result)"
  fi
  if [ "$advisory_count" -gt 0 ]; then
    advisories_len="$(printf '%s\n' "$json" | jq -r '(.advisories // []) | length' 2>/dev/null)" || error_exit "failed to read advisories length (jq parse error)"
    if [ -z "$advisories_len" ]; then
      error_exit "failed to read advisories length (empty result)"
    fi
    if [ "$advisories_len" -lt "$advisory_count" ]; then
      printf 'WARN: advisory_count=%d but only %d advisories[] entries recorded; protocol requires one entry per finding\n' \
        "$advisory_count" "$advisories_len" >&2
    fi
    bulk_rationale="$(printf '%s\n' "$json" | jq -r '
      (.advisories // [])
      | map(select((.rationale // "") | test("reviewed and accepted|in bulk"; "i")))
      | length
    ' 2>/dev/null)" || error_exit "failed to check bulk rationale (jq parse error)"
    if [ -z "$bulk_rationale" ]; then
      error_exit "failed to check bulk rationale (empty result)"
    fi
    if [ "$bulk_rationale" -gt 0 ]; then
      printf 'WARN: %d advisory entry/entries contain generic bulk-acceptance rationale; per-finding rationale is required by protocol\n' \
        "$bulk_rationale" >&2
    fi
  fi
}

render_epic_ledger() {
  local json="$1"

  if printf '%s\n' "$json" | jq -e '.epic_not_applicable == true' >/dev/null; then
    {
      printf '%s\n' "$EPIC_MARKER"
      printf '## /run-epic Epic Ledger\n\n'
      printf 'Not applicable: this run used an explicit item list with no parent epic.\n'
    }
    return
  fi

  if ! printf '%s\n' "$json" | jq -e '.epic.number and (.items | type == "array")' >/dev/null; then
    error_exit "missing required epic ledger fields"
  fi

  {
    printf '%s\n' "$EPIC_MARKER"
    printf '## /run-epic Epic Ledger\n\n'
    printf '%s\n\n' "$(printf '%s\n' "$json" | jq -r '"Epic: #" + (.epic.number | tostring) + " - " + (.epic.title // "")')"
    printf '| Issue | PR | Tracker status | Risk | Review | Decision | Merge / cleanup | Notes |\n'
    printf '| --- | --- | --- | --- | --- | --- | --- | --- |\n'
    printf '%s\n' "$json" | jq -r "$table_cell_filter"'
      (.invocation_policy // {}) as $rootInvocationPolicy |
      ($rootInvocationPolicy.effective_policy // $rootInvocationPolicy.effectivePolicy // {}) as $rootEffectivePolicy |
      def policy_note($policy):
        if (($policy | type) == "object") and (($policy | length) > 0) then
          "Effective policy: mayStartBacklog=" + (($policy.mayStartBacklog // "") | tostring) +
          ", delegateReview=" + (($policy.delegateReview // "") | tostring) +
          ", mayMerge=" + (($policy.mayMerge // "") | tostring) +
          ", maxRisk=" + (($policy.maxRisk // "") | tostring) +
          ", base=" + (($policy.base // "") | tostring)
        else "" end;
      def checkpoint_note($checkpoints):
        if (($checkpoints | type) == "array") and (($checkpoints | length) > 0) then
          "Checkpoints: " + (
            $checkpoints
            | map("#" + (.item_number|tostring) + " " + (.stage // "") + "/" + (.domain // "") + "=" + (.satisfaction_state // "pending"))
            | join(", ")
          )
        else "" end;
      def notes_with_policy($base; $policy; $gate; $checkpoints):
        [
          ($base // ""),
          policy_note($policy),
          checkpoint_note($checkpoints),
          (if (($gate // "") | tostring | length) > 0 then "Stop gate: " + ($gate | tostring) else "" end)
        ]
        | map(select((. | tostring | length) > 0))
        | join("\n");
      def item_checkpoints($item; $rootPolicy):
        if (($item.checkpoints // $item.effective_checkpoints // null) != null) then
          ($item.checkpoints // $item.effective_checkpoints // [])
        else
          ($rootPolicy.checkpoints // [] | map(select((.item_number | tonumber) == ($item.issue_number | tonumber))))
        end;
      .items[] |
      (.effective_policy // .effectivePolicy // $rootEffectivePolicy) as $effectivePolicy |
      item_checkpoints(.; $rootEffectivePolicy) as $itemCheckpoints |
      (.stop_gate // .stopGate // .final_stop_gate // .finalStopGate // "") as $stopGate |
      "| #" + (.issue_number | tostring) + " " + ((.title // "") | cell) +
      " | " + (if .pr_number then "#" + (.pr_number | tostring) else "-" end) +
      " | " + ((.tracker_status // "") | cell) +
      " | " + ((.risk_level // "") | cell) +
      " | " + ((.review_result // "") | cell) +
      " | " + ((.decision // "") | cell) +
      " | " + ((.merge_cleanup // "") | cell) +
      " | " + (notes_with_policy(.notes; $effectivePolicy; $stopGate; $itemCheckpoints) | cell) + " |"
    '
  } | redact_text
}

render_reviewer_access_bypass() {
  local json="$1"
  local missing
  local missing_status=0

  # See the identical note in render_pr_disposition(): this function is
  # called directly (render-reviewer-access-bypass) and via command
  # substitution (apply-reviewer-access-bypass). Every dotted lookup is
  # wrapped in `try ... catch null` so a wrong-typed value reports as
  # missing instead of crashing jq, and the jq exit status is captured
  # explicitly via `||` rather than relied upon via `set -e` propagation.
  missing="$(printf '%s\n' "$json" | jq -r '
    [
      ["authorization.authorized_by", (try (.authorization.authorized_by // .authorization.authorizedBy) catch null)],
      ["authorization.authorized_at", (try (.authorization.authorized_at // .authorization.authorizedAt) catch null)],
      ["authorization.authorization_text", (try (.authorization.authorization_text // .authorization.authorizationText) catch null)],
      ["pr.number", (try .pr.number catch null)],
      ["pr.head_sha", (try (.pr.head_sha // .pr.headSha) catch null)],
      ["evidence_fingerprint", (try (.evidence_fingerprint // .evidenceFingerprint) catch null)],
      ["ci.result", (try (.ci.result // .ci_result) catch null)],
      ["reviewer.result", (try (.reviewer.result // .reviewer.status) catch null)],
      ["blocked_check.name", (try (.blocked_check.name // .blockedCheck.name) catch null)],
      ["access.evidence", (try (.access.evidence // .accessRestriction.evidence) catch null)],
      ["access.remediation_status", (try (.access.remediation_status // .access.remediationStatus) catch null)],
      ["access.bypass_reason", (try (.access.bypass_reason // .access.bypassReason // .accessRestriction.bypassReason) catch null)],
      ["proposed_action", (try (.proposed_action // .proposedAction) catch null)],
      ["state", (try .state catch null)]
    ]
    | map(select(.[1] == null or (.[1] | tostring | length == 0)) | .[0])
    | join(", ")
  ')" || missing_status=$?
  if [ "$missing_status" -ne 0 ]; then
    error_exit "failed to evaluate required reviewer access-bypass fields (jq exit ${missing_status})"
  fi
  if [ -n "$missing" ]; then
    error_exit "missing required reviewer access-bypass fields: $missing"
  fi

  {
    printf '%s\n' "$REVIEWER_ACCESS_BYPASS_MARKER"
    printf '## Reviewer Access Bypass Audit\n\n'
    printf '%s\n' "$json" | jq -r '
      "- State: " + (.state | tostring),
      "- Authorized by: " + ((.authorization.authorized_by // .authorization.authorizedBy) | tostring),
      "- Authorized at: " + ((.authorization.authorized_at // .authorization.authorizedAt) | tostring),
      "- Authorization text: " + ((.authorization.authorization_text // .authorization.authorizationText) | tostring),
      "- PR: #" + (.pr.number | tostring),
      "- Head SHA: `" + ((.pr.head_sha // .pr.headSha) | tostring) + "`",
      "- Evidence fingerprint: `" + ((.evidence_fingerprint // .evidenceFingerprint) | tostring) + "`",
      "- Proposed action: `" + ((.proposed_action // .proposedAction) | tostring) + "`"
    '
    printf '\n### Evidence\n\n'
    printf '%s\n' "$json" | jq -r '
      "- CI result: " + ((.ci.result // .ci_result) | tostring),
      "- Reviewer result: " + ((.reviewer.result // .reviewer.status) | tostring),
      "- Reviewer blocking count: " + ((.reviewer.blocking_count // .reviewer.blockingCount // 0) | tostring),
      "- Blocked check: " + ((.blocked_check.name // .blockedCheck.name) | tostring) + " (" + ((.blocked_check.state // .blockedCheck.state // .blocked_check.conclusion // .blockedCheck.conclusion // "unknown") | tostring) + ")",
      "- Access evidence: " + ((.access.evidence // .accessRestriction.evidence) | tostring),
      "- Remediation: " + ((.access.remediation_status // .access.remediationStatus) | tostring),
      "- Bypass reason: " + ((.access.bypass_reason // .access.bypassReason // .accessRestriction.bypassReason) | tostring)
    '
    printf '\n### Attempt Result\n\n'
    printf '%s\n' "$json" | jq -r '
      "- Result: " + ((.attempt.result // "not_attempted") | tostring),
      "- Command exit: " + ((.attempt.exit_code // .attempt.exitCode // "n/a") | tostring),
      "- Live PR state: " + ((.attempt.live_pr_state // .attempt.livePrState // "not_recorded") | tostring)
    '
  } | redact_text
}

validate_reviewer_access_bypass_scope() {
  local json="$1"
  local expected_pr="$2"

  printf '%s\n' "$json" | jq -er --arg expected_pr "$expected_pr" '
    (.pr.number | tostring) as $input_pr |
    ((.pr.head_sha // .pr.headSha) | tostring) as $head_sha |
    ((.proposed_action // .proposedAction) | tostring) as $action |
    ($head_sha | test("^[0-9a-f]{40}$"))
    and ($action == ("gh pr merge " + $expected_pr + " --admin --match-head-commit " + $head_sha))
    and ($input_pr == $expected_pr)
  ' >/dev/null || error_exit "reviewer access-bypass input must target PR #${expected_pr} and proposed action 'gh pr merge ${expected_pr} --admin --match-head-commit <head-sha>'"
}

find_marker_comment_id() {
  local target="$1"
  local marker="$2"
  local repo comments

  repo="$(repo_slug)"
  if ! comments="$(gh api --paginate --slurp "repos/${repo}/issues/${target}/comments?per_page=100" 2>/dev/null)"; then
    error_exit "failed to read comments for issue/PR #$target"
  fi
  printf '%s\n' "$comments" |
    jq -r --arg marker "$marker" '[.[][]? | select((.body // "") | contains($marker))][0].id // empty'
}

apply_comment() {
  local target="$1"
  local marker="$2"
  local body="$3"
  local repo comment_id

  require_gh
  repo="$(repo_slug)"
  comment_id="$(find_marker_comment_id "$target" "$marker")"
  if [ -n "$comment_id" ]; then
    jq -n --arg body "$body" '{body: $body}' |
      gh api -X PATCH "repos/${repo}/issues/comments/${comment_id}" --input - >/dev/null
    printf 'UPDATED_COMMENT_ID=%s\n' "$comment_id"
  else
    jq -n --arg body "$body" '{body: $body}' |
      gh api -X POST "repos/${repo}/issues/${target}/comments" --input - >/dev/null
    printf 'CREATED_COMMENT=1\n'
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --input)
      require_value "$@"
      input_file="$2"
      shift 2
      ;;
    --pr)
      require_value "$@"
      pr_number="$2"
      shift 2
      ;;
    --epic)
      require_value "$@"
      epic_number="$2"
      shift 2
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

case "$command" in
  render-pr-disposition|apply-pr-disposition|render-epic-ledger|apply-epic-ledger|render-reviewer-access-bypass|apply-reviewer-access-bypass)
    ;;
  *)
    echo "ERROR: unknown or missing subcommand." >&2
    usage >&2
    exit 64
    ;;
esac

[ -n "$input_file" ] || error_exit "--input is required"
input_json="$(load_input_json "$input_file")"

case "$command" in
  render-pr-disposition)
    validate_advisories "$input_json"
    warn_per_finding_advisories "$input_json"
    render_pr_disposition "$input_json"
    ;;
  apply-pr-disposition)
    if [ -z "$pr_number" ] || ! is_positive_int "$pr_number"; then
      error_exit "--pr must be a positive integer"
    fi
    validate_advisories "$input_json"
    warn_per_finding_advisories "$input_json"
    body="$(render_pr_disposition "$input_json")" || error_exit "failed to render PR disposition (see error above)"
    apply_comment "$pr_number" "$PR_MARKER" "$body"
    ;;
  render-epic-ledger)
    render_epic_ledger "$input_json"
    ;;
  apply-epic-ledger)
    if [ -z "$epic_number" ] || ! is_positive_int "$epic_number"; then
      error_exit "--epic must be a positive integer"
    fi
    body="$(render_epic_ledger "$input_json")" || error_exit "failed to render epic ledger (see error above)"
    apply_comment "$epic_number" "$EPIC_MARKER" "$body"
    ;;
  render-reviewer-access-bypass)
    render_reviewer_access_bypass "$input_json"
    ;;
  apply-reviewer-access-bypass)
    if [ -z "$pr_number" ] || ! is_positive_int "$pr_number"; then
      error_exit "--pr must be a positive integer"
    fi
    validate_reviewer_access_bypass_scope "$input_json" "$pr_number"
    body="$(render_reviewer_access_bypass "$input_json")" || error_exit "failed to render reviewer access-bypass audit (see error above)"
    apply_comment "$pr_number" "$REVIEWER_ACCESS_BYPASS_MARKER" "$body"
    ;;
esac
