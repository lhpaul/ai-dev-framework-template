#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-epic-delegated-gate.sh --input <file> [--policy <file>] [--json]

Evaluates whether a delegated /run-epic candidate PR may proceed to the
repository merge protocol. The gate is read-only: it does not run reviewers,
poll CI, edit labels, update trackers, create comments, merge PRs, close
issues, or delete branches.
EOF
}

input_file=""
policy_file=""
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
  state_json="$(printf '%s\n' "$state_json" | jq --argjson policy "$policy_json" '.policy = $policy')"
fi

decision_json="$(printf '%s\n' "$state_json" | jq '
  def policy: if (.policy | type) == "object" then .policy else {} end;
  def labels: (.pr.labels // []);
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
  def risk_merge_permitted:
    if (.risk // {}) | has("mergePermitted") then .risk.mergePermitted
    elif (.risk // {}) | has("merge_permitted") then .risk.merge_permitted
    else false
    end;
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
  (if ((.statusChecks // []) | length) == 0
   then add_reason($reasons; "required CI state is missing")
   else $reasons end) as $reasons |
  (if ((.statusChecks // []) | map(select(success_check | not)) | length) > 0
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
  (if risk_merge_permitted != true
   then add_reason($reasons; "risk gate does not permit merge")
   else $reasons end) as $reasons |
  (if (.pr.auditDispositionPresent // false) != true
   then add_reason($reasons; "PR disposition audit is missing")
   else $reasons end) as $reasons |
  (reason_count($reasons)) as $count |
  {
    decision: (
      if $count == 0 then "merge_allowed"
      elif ($reasons | any(test("reviewer blocking|CI checks|unresolved blocking|advisories"))) then "fix_required"
      elif ($reasons | any(test("authority|risk gate|needs-setup|not in the resolved|Backlog"))) then "human_required"
      else "blocked"
      end
    ),
    mergePermitted: ($count == 0),
    reasons: $reasons,
    nextAction: (
      if $count == 0 then "record merge evidence and use the repository merge protocol"
      elif ($reasons | any(test("reviewer blocking|CI checks|unresolved blocking|advisories"))) then "remove readiness labels, fix, rerun validation, reviewer loop, CI loop, and this gate"
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
')"

if [ "$json_output" -eq 1 ]; then
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
