#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-epic-policy-recommender.sh --scope <resolver-json> --original-command <text> [--base <branch>] [--delegate-review] [--may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>] [--json]

Derives a read-only recommended /run-epic autonomy policy from resolver output.
The helper does not update trackers, create branches, open PRs, edit labels,
post comments, merge PRs, close issues, or delete branches.
EOF
}

scope_file=""
original_command=""
base_override=""
delegate_review_override=""
may_merge_override=""
may_start_backlog_override=""
max_risk_override=""
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

is_boolean() {
  case "$1" in
    true|false) return 0 ;;
    *) return 1 ;;
  esac
}

valid_max_risk() {
  case "$1" in
    low|medium|high) return 0 ;;
    *) return 1 ;;
  esac
}

load_scope_json() {
  local file="$1"
  if [ ! -f "$file" ]; then
    error_exit "scope file not found: $file"
  fi
  if [ ! -s "$file" ]; then
    error_exit "scope file is empty: $file"
  fi
  jq -c '.' "$file" 2>/dev/null || error_exit "scope file is not valid JSON: $file"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --scope)
      require_value "$@"
      scope_file="$2"
      shift 2
      ;;
    --original-command)
      require_value "$@"
      original_command="$2"
      shift 2
      ;;
    --base)
      require_value "$@"
      base_override="$2"
      shift 2
      ;;
    --delegate-review)
      delegate_review_override="true"
      shift
      ;;
    --may-merge)
      may_merge_override="true"
      shift
      ;;
    --may-start-backlog)
      require_value "$@"
      may_start_backlog_override="$2"
      shift 2
      ;;
    --max-risk)
      require_value "$@"
      max_risk_override="$2"
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

[ -n "$scope_file" ] || error_exit "--scope is required"
[ -n "$original_command" ] || error_exit "--original-command is required"

if [ -n "$may_start_backlog_override" ] && ! is_boolean "$may_start_backlog_override"; then
  echo "ERROR: --may-start-backlog must be true or false." >&2
  exit 64
fi
if [ -n "$max_risk_override" ] && ! valid_max_risk "$max_risk_override"; then
  echo "ERROR: --max-risk must be one of low, medium, or high." >&2
  exit 64
fi

scope_json="$(load_scope_json "$scope_file")"

if ! printf '%s\n' "$scope_json" | jq -e '
  (.groups | type) == "object" and
  (.items | type) == "array" and
  (.policy | type) == "object"
' >/dev/null; then
  error_exit "scope JSON must include object fields groups and policy plus array field items"
fi

reviewers="$(workflow_config_review_on_draft_runner "$(workflow_config_file)" 2>/dev/null || true)"
reviewer_count="$(printf '%s\n' "$reviewers" | sed '/^$/d' | wc -l | tr -d ' ')"

recommendation_json="$(printf '%s\n' "$scope_json" | jq -c \
  --arg originalCommand "$original_command" \
  --arg baseOverride "$base_override" \
  --arg delegateReviewOverride "$delegate_review_override" \
  --arg mayMergeOverride "$may_merge_override" \
  --arg mayStartBacklogOverride "$may_start_backlog_override" \
  --arg maxRiskOverride "$max_risk_override" \
  --argjson reviewerCount "$reviewer_count" '
  def bool_override($v): if $v == "" then null elif $v == "true" then true else false end;
  def risk_rank($risk): {"low": 1, "medium": 2, "high": 3}[$risk] // 0;
  def max_risk($a; $b): if risk_rank($a) >= risk_rank($b) then $a else $b end;
  def item_text:
    [.items[]? | ((.title // "") + " " + (.type // "") + " " + ((.labels // []) | join(" ")) + " " + (.integrationBranchLabel // ""))]
    | join(" ")
    | ascii_downcase;
  def has_backlog: [.items[]? | select((.status // "") == "Backlog")] | length > 0;
  def has_dependency_blocker: [.items[]? | select((.dependencies.state // "") == "blocked")] | length > 0;
  def has_ambiguous: ((.groups.ambiguous // []) | length) > 0 or (.baseAmbiguous // false) == true;
  def has_blocked: ((.groups.blocked // []) | length) > 0 or has_dependency_blocker;
  def has_workflow_signal:
    item_text | test("run-epic|workflow|orchestrat|merge|cleanup|delegated|audit|risk|reviewer|gate|tooling|script");
  def has_low_doc_signal:
    item_text | test("spec|plan|docs|documentation|smoke");
  def recommended_start:
    if has_backlog and (has_blocked | not) and (has_ambiguous | not) then true else false end;
  def recommended_review:
    $reviewerCount > 0;
  def recommended_risk:
    if has_workflow_signal then "medium"
    elif has_low_doc_signal then "low"
    else "low"
    end;
  def recommended_merge:
    recommended_review and (has_ambiguous | not) and (recommended_risk != "high");
  def recommended_base:
    if (.baseAmbiguous // false) == true then null else (.baseBranch // null) end;
  def source_for($override): if $override == "" then "recommended" else "explicit" end;
  def value_bool($override; $recommended):
    if $override == "" then $recommended else bool_override($override) end;
  def value_string($override; $recommended):
    if $override == "" then $recommended else $override end;

  (recommended_start) as $recStart |
  (recommended_review) as $recReview |
  (recommended_merge) as $recMerge |
  (recommended_risk) as $recRisk |
  (recommended_base) as $recBase |
  {
    originalCommand: $originalCommand,
    scope: {
      source: .scopeSource,
      epicNumber: .epicNumber,
      itemInput: .itemInput,
      baseReason: .baseReason,
      itemCount: (.items | length),
      groups: {
        eligible: ((.groups.eligible // []) | length),
        blocked: ((.groups.blocked // []) | length),
        alreadyMerged: ((.groups.already_merged // []) | length),
        inReview: ((.groups.in_review // []) | length),
        ambiguous: ((.groups.ambiguous // []) | length)
      }
    },
    recommendedPolicy: {
      mayStartBacklog: $recStart,
      delegateReview: $recReview,
      mayMerge: $recMerge,
      maxRisk: $recRisk,
      base: $recBase
    },
    selectedPolicy: {
      mayStartBacklog: value_bool($mayStartBacklogOverride; $recStart),
      delegateReview: value_bool($delegateReviewOverride; $recReview),
      mayMerge: value_bool($mayMergeOverride; $recMerge),
      maxRisk: value_string($maxRiskOverride; $recRisk),
      base: value_string($baseOverride; $recBase)
    },
    effectivePolicy: {
      mayStartBacklog: value_bool($mayStartBacklogOverride; $recStart),
      delegateReview: value_bool($delegateReviewOverride; $recReview),
      mayMerge: value_bool($mayMergeOverride; $recMerge),
      maxRisk: value_string($maxRiskOverride; $recRisk),
      base: value_string($baseOverride; $recBase)
    },
    fieldSources: {
      mayStartBacklog: source_for($mayStartBacklogOverride),
      delegateReview: source_for($delegateReviewOverride),
      mayMerge: source_for($mayMergeOverride),
      maxRisk: source_for($maxRiskOverride),
      base: source_for($baseOverride)
    },
    requiresConfirmation: ((
      [$mayStartBacklogOverride, $delegateReviewOverride, $mayMergeOverride, $maxRiskOverride, $baseOverride]
      | any(. == "")
    ) or has_ambiguous),
    confirmationReason: (
      if has_ambiguous then "scope or base is ambiguous; confirm before mutation"
      elif ([$mayStartBacklogOverride, $delegateReviewOverride, $mayMergeOverride, $maxRiskOverride, $baseOverride] | any(. == "")) then
        "one or more autonomy policy values were inferred from resolved scope"
      else "all autonomy policy values were explicit"
      end
    ),
    rationale: {
      mayStartBacklog: (
        if $recStart then "requested scope includes Backlog work with no detected dependency or ambiguity"
        elif has_backlog then "Backlog work is present but blocked or ambiguous"
        else "resolved scope has no Backlog work to start"
        end
      ),
      delegateReview: (
        if $recReview then "configured internal reviewers are available for this runner"
        else "no configured internal reviewer was found"
        end
      ),
      mayMerge: (
        if $recMerge then "delegated review is available and scope is unambiguous"
        else "merge should wait for human authority, reviewer setup, or scope clarification"
        end
      ),
      maxRisk: (
        if $recRisk == "medium" then "workflow/tooling changes can be medium risk when why-safe evidence is produced"
        else "scope appears limited to docs, specs, plans, tests, or narrow text"
        end
      ),
      base: (
        if $recBase == null then "base branch could not be inferred unambiguously"
        else "base branch inferred by resolver: " + ($recBase | tostring)
        end
      )
    },
    copyPasteCommand: (
      $originalCommand +
      (if value_bool($delegateReviewOverride; $recReview) then " --delegate-review" else "" end) +
      (if value_bool($mayMergeOverride; $recMerge) then " --may-merge" else "" end) +
      " --may-start-backlog " + (value_bool($mayStartBacklogOverride; $recStart) | tostring) +
      " --max-risk " + (value_string($maxRiskOverride; $recRisk) | tostring) +
      (if value_string($baseOverride; $recBase) == null then "" else " --base " + (value_string($baseOverride; $recBase) | tostring) end)
    ),
    readOnlyGuarantee: "No tracker updates, branch creation, PR edits, labels, comments, merges, issue closure, or branch deletion were performed."
  }
')"

if [ "$json_output" -eq 1 ]; then
  printf '%s\n' "$recommendation_json"
  exit 0
fi

printf 'Run Epic Policy Recommendation\n'
printf 'Requires confirmation: %s\n' "$(printf '%s\n' "$recommendation_json" | jq -r '.requiresConfirmation')"
printf 'Reason: %s\n' "$(printf '%s\n' "$recommendation_json" | jq -r '.confirmationReason')"
printf 'Effective policy:\n'
printf '%s\n' "$recommendation_json" | jq -r '
  "- May start Backlog: " + (.effectivePolicy.mayStartBacklog | tostring) + " (" + .fieldSources.mayStartBacklog + ")",
  "- Delegated review: " + (.effectivePolicy.delegateReview | tostring) + " (" + .fieldSources.delegateReview + ")",
  "- May merge: " + (.effectivePolicy.mayMerge | tostring) + " (" + .fieldSources.mayMerge + ")",
  "- Max risk: " + (.effectivePolicy.maxRisk | tostring) + " (" + .fieldSources.maxRisk + ")",
  "- Base: " + ((.effectivePolicy.base // "ambiguous") | tostring) + " (" + .fieldSources.base + ")"
'
printf 'Rationale:\n'
printf '%s\n' "$recommendation_json" | jq -r '
  "- Backlog: " + .rationale.mayStartBacklog,
  "- Review: " + .rationale.delegateReview,
  "- Merge: " + .rationale.mayMerge,
  "- Risk: " + .rationale.maxRisk,
  "- Base: " + .rationale.base
'
printf 'Copy-paste equivalent: %s\n' "$(printf '%s\n' "$recommendation_json" | jq -r '.copyPasteCommand')"
printf 'Read-only: %s\n' "$(printf '%s\n' "$recommendation_json" | jq -r '.readOnlyGuarantee')"
