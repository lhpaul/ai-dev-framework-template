#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"
RUN_EPIC_SCOPE_RESOLVER_CMD="${RUN_EPIC_SCOPE_RESOLVER_CMD:-$SCRIPT_DIR/run-epic-scope-resolver.sh}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-item-scope-resolver.sh --target <token> [--base <branch>] [--delegate-review] [--may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>] [--json]
  ./scripts/development-workflow/run-item-scope-resolver.sh --issue <issue-id> [--base <branch>] ... [--json]
  ./scripts/development-workflow/run-item-scope-resolver.sh --branch <name> [--base <branch>] ... [--json]
  ./scripts/development-workflow/run-item-scope-resolver.sh --pr <number> [--base <branch>] ... [--json]
  ./scripts/development-workflow/run-item-scope-resolver.sh --development <path> [--base <branch>] ... [--json]

Resolves exactly one non-epic workflow item into scope JSON compatible with
run-epic-policy-recommender.sh (scopeSource=item). Read-only — no tracker,
branch, PR, merge, or cleanup mutation.
EOF
}

json_output=0
target_token=""
issue_number=""
branch_name=""
pr_number=""
development_path=""
base_override=""
delegate_review=0
may_merge=0
may_start_backlog="false"
max_risk="low"

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

is_linear_identifier() {
  [[ "$1" =~ ^[A-Za-z]+-[0-9]+$ ]]
}

tracker_provider() {
  local config_file raw_provider
  config_file="$(workflow_effective_config_file 2>/dev/null)" || config_file=""
  if [ -n "$config_file" ]; then
    raw_provider="$(workflow_config_provider issue_tracker "$config_file")"
  else
    raw_provider="$(workflow_issue_tracker_provider_raw)"
  fi
  workflow_normalize_issue_tracker_provider "$raw_provider"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

issue_from_branch() {
  local b="$1"
  if [[ "$b" =~ ^(fix|feature|hotfix|refactor)/([0-9]+)($|-) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  if [[ "$b" =~ ^(fix|feature|hotfix|refactor)/([a-zA-Z]{2,6}-([0-9]+))($|-) ]]; then
    printf '%s\n' "${BASH_REMATCH[3]}"
    return 0
  fi
  if [[ "$b" =~ ^(spec|implementation-plan|plan)/([0-9]+)($|-) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  if [[ "$b" =~ ^(spec|implementation-plan|plan)/([a-zA-Z]{2,6}-([0-9]+))($|-) ]]; then
    printf '%s\n' "${BASH_REMATCH[3]}"
    return 0
  fi
  return 1
}

is_epic_issue() {
  local num="$1"
  if ! have_cmd gh; then
    echo "run-item-scope-resolver: gh CLI is required to verify non-epic scope for issue #$num" >&2
    return 2
  fi
  local sub_count=0 issue_type=0
  sub_count="$(gh issue view "$num" --json subIssues --jq '.subIssues.totalCount' 2>/dev/null)" || sub_count=0
  case "${sub_count:-}" in
    ''|*[!0-9]*) sub_count="0" ;;
  esac
  issue_type="$(gh issue view "$num" --json labels \
    --jq '[.labels[].name] | map(ascii_downcase) | map(select(. == "epic")) | length' 2>/dev/null)" || issue_type=0
  case "${issue_type:-}" in
    ''|*[!0-9]*) issue_type="0" ;;
  esac
  if [ "$sub_count" -gt 0 ] || [ "$issue_type" -gt 0 ]; then
    return 0
  fi
  return 1
}

resolve_token_kind() {
  local token="$1"
  local repo_root pr_num pr_state issue_state
  token="${token#./}"
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || repo_root=""

  if [ "$(tracker_provider)" = "linear" ] && is_linear_identifier "$token"; then
    printf 'issue'
    return 0
  fi

  if [ -n "$repo_root" ] && [ -d "$repo_root/$token" ] && [[ "$token" == docs/specs/developments/* ]]; then
    printf 'dev_folder'
    return 0
  fi

  pr_num="${token#\#}"
  if is_positive_int "$pr_num" && have_cmd gh; then
    pr_state="$(gh pr view "$pr_num" --json state --jq '.state' 2>/dev/null)" || true # workflow-shell-guard: allow SH001 - type probe; failure expected when target is not a PR
    if [ -n "$pr_state" ]; then
      printf 'pr'
      return 0
    fi
    issue_state="$(gh issue view "$pr_num" --json state --jq '.state' 2>/dev/null)" || true # workflow-shell-guard: allow SH001 - type probe; failure expected when target is not an issue
    if [ -n "$issue_state" ]; then
      printf 'issue'
      return 0
    fi
    return 1
  fi

  case "$token" in
    feature/*|fix/*|refactor/*|hotfix/*|spec/*|implementation-plan/*|plan/*)
      if git show-ref --verify --quiet "refs/remotes/origin/$token" 2>/dev/null \
        || git show-ref --verify --quiet "refs/heads/$token" 2>/dev/null; then
        printf 'branch'
        return 0
      fi
      return 1
      ;;
  esac
  return 1
}

issue_from_development_path() {
  local path="$1"
  local slug issue
  slug="$(basename "$path" | sed 's/^[0-9]\{14\}_//')"
  if [[ "$slug" =~ ^([0-9]+)- ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    if issue_from_branch "$ref" >/dev/null 2>&1; then
      issue="$(issue_from_branch "$ref")"
      printf '%s\n' "$issue"
      return 0
    fi
  done < <(git show-ref 2>/dev/null | sed -n 's|.*refs/remotes/origin/||p' | grep -F "$slug")
  return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      require_value "$@"
      target_token="$2"
      shift 2
      ;;
    --issue)
      require_value "$@"
      issue_number="$2"
      shift 2
      ;;
    --branch)
      require_value "$@"
      branch_name="$2"
      shift 2
      ;;
    --pr)
      require_value "$@"
      pr_number="$2"
      shift 2
      ;;
    --development)
      require_value "$@"
      development_path="$2"
      shift 2
      ;;
    --base)
      require_value "$@"
      base_override="$2"
      shift 2
      ;;
    --delegate-review)
      delegate_review=1
      shift
      ;;
    --may-merge)
      may_merge=1
      shift
      ;;
    --may-start-backlog)
      require_value "$@"
      may_start_backlog="$2"
      shift 2
      ;;
    --max-risk)
      require_value "$@"
      max_risk="$2"
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

inputs=0
[ -n "$target_token" ] && inputs=$((inputs + 1))
[ -n "$issue_number" ] && inputs=$((inputs + 1))
[ -n "$branch_name" ] && inputs=$((inputs + 1))
[ -n "$pr_number" ] && inputs=$((inputs + 1))
[ -n "$development_path" ] && inputs=$((inputs + 1))

if [ "$inputs" -ne 1 ]; then
  usage >&2
  exit 64
fi

if ! is_boolean "$may_start_backlog"; then
  echo "ERROR: --may-start-backlog must be true or false." >&2
  exit 64
fi
if ! valid_max_risk "$max_risk"; then
  echo "ERROR: --max-risk must be one of low, medium, or high." >&2
  exit 64
fi

item_input=""
resolved_issue=""

if [ -n "$issue_number" ]; then
  if is_positive_int "$issue_number"; then
    resolved_issue="$issue_number"
  elif [ "$(tracker_provider)" = "linear" ] && is_linear_identifier "$issue_number"; then
    resolved_issue="$issue_number"
  else
    error_exit "invalid --issue identifier: $issue_number"
  fi
  item_input="$issue_number"
elif [ -n "$target_token" ]; then
  item_input="$target_token"
  kind="$(resolve_token_kind "$target_token")" || error_exit "could not resolve --target '$target_token'"
  case "$kind" in
    issue)
      if is_linear_identifier "$target_token"; then
        resolved_issue="$target_token"
      else
        resolved_issue="${target_token#\#}"
      fi
      ;;
    pr)
      pr_num="${target_token#\#}"
      head="$(gh pr view "$pr_num" --json headRefName --jq '.headRefName' 2>/dev/null)" || error_exit "could not read PR #$pr_num"
      resolved_issue="$(issue_from_branch "$head")" || error_exit "could not extract issue from PR branch $head"
      ;;
    branch)
      resolved_issue="$(issue_from_branch "$target_token")" || error_exit "could not extract issue number from branch $target_token"
      ;;
    dev_folder)
      resolved_issue="$(issue_from_development_path "$target_token")" || error_exit "could not resolve issue from development path $target_token"
      ;;
    *)
      error_exit "unsupported resolved kind for target"
      ;;
  esac
elif [ -n "$branch_name" ]; then
  item_input="$branch_name"
  resolved_issue="$(issue_from_branch "$branch_name")" || error_exit "could not extract issue number from branch $branch_name"
elif [ -n "$pr_number" ]; then
  if ! is_positive_int "$pr_number"; then
    error_exit "invalid --pr number: $pr_number"
  fi
  item_input="$pr_number"
  head="$(gh pr view "$pr_number" --json headRefName --jq '.headRefName' 2>/dev/null)" || error_exit "could not read PR #$pr_number"
  resolved_issue="$(issue_from_branch "$head")" || error_exit "could not extract issue from PR branch $head"
elif [ -n "$development_path" ]; then
  item_input="$development_path"
  resolved_issue="$(issue_from_development_path "$development_path")" || error_exit "could not resolve issue from $development_path"
fi

if is_positive_int "$resolved_issue"; then
  set +e
  is_epic_issue "$resolved_issue"
  epic_check=$?
  set -e
  if [ "$epic_check" -eq 0 ]; then
    error_exit "issue #$resolved_issue is epic-like; use /run-epic or run-epic-scope-resolver instead"
  elif [ "$epic_check" -eq 2 ]; then
    error_exit "cannot verify epic scope for issue #$resolved_issue without gh CLI"
  fi
fi

if ! is_positive_int "$resolved_issue"; then
  provider="$(tracker_provider)"
  if [ "$provider" != "linear" ]; then
    error_exit "non-numeric issue identifiers are supported only when issue_tracker.provider is linear"
  fi
  base_branch="${base_override:-develop}"
  base_reason="default develop base; Linear tracker details are deferred to the orchestrator"
  if [ -n "$base_override" ]; then
    base_reason="supplied --base override"
  fi
  out_json="$(jq -n \
    --arg itemInput "$item_input" \
    --arg resolvedIssue "$resolved_issue" \
    --arg baseBranch "$base_branch" \
    --arg baseReason "$base_reason" \
    --arg maxRisk "$max_risk" \
    --arg mayStartBacklog "$may_start_backlog" \
    --argjson delegateReview "$delegate_review" \
    --argjson mayMerge "$may_merge" \
    '{
      scopeSource: "item",
      epicNumber: null,
      itemInput: $itemInput,
      resolvedIssueNumber: null,
      resolvedIssueIdentifier: $resolvedIssue,
      trackerReadDeferred: true,
      baseBranch: $baseBranch,
      baseAmbiguous: false,
      baseReason: $baseReason,
      policy: {
        delegateReview: ($delegateReview == 1),
        mayMerge: ($mayMerge == 1),
        mayStartBacklog: ($mayStartBacklog == "true"),
        maxRisk: $maxRisk
      },
      readOnlyGuarantee: "No tracker status, branch, PR, merge, issue-close, or cleanup mutation was performed.",
      groups: {
        eligible: [{
          number: $resolvedIssue,
          identifier: $resolvedIssue,
          title: "",
          body: "",
          issueState: "",
          issueStateReason: "",
          labels: [],
          integrationBranchLabel: "",
          status: "Backlog",
          type: "",
          priority: "",
          dependencies: {state: "none", issues: []},
          pullRequests: {open: [], merged: []},
          group: "eligible",
          trackerReadDeferred: true,
          ambiguityReason: null
        }],
        blocked: [],
        already_merged: [],
        in_review: [],
        ambiguous: [],
        out_of_scope: []
      },
      items: [{
        number: $resolvedIssue,
        identifier: $resolvedIssue,
        title: "",
        body: "",
        issueState: "",
        issueStateReason: "",
        labels: [],
        integrationBranchLabel: "",
        status: "Backlog",
        type: "",
        priority: "",
        dependencies: {state: "none", issues: []},
        pullRequests: {open: [], merged: []},
        group: "eligible",
        trackerReadDeferred: true,
        ambiguityReason: null
      }]
    }')"
  if [ "$json_output" -eq 1 ]; then
    printf '%s\n' "$out_json"
    exit 0
  fi
  printf 'PROVIDER=linear\n'
  printf 'TRACKER_READ_DEFERRED=yes\n'
  printf 'Run Item Scope Resolver\n'
  printf 'Resolved issue: %s\n' "$resolved_issue"
  printf 'Item input: %s\n' "$item_input"
  printf 'Base branch: %s (%s)\n' "$base_branch" "$base_reason"
  printf -- '- eligible %s [Linear tracker details deferred]\n' "$resolved_issue"
  printf 'Read-only: %s\n' "$(printf '%s\n' "$out_json" | jq -r '.readOnlyGuarantee')"
  exit 0
fi

resolver_args=(
  --items "$resolved_issue"
  --may-start-backlog "$may_start_backlog"
  --max-risk "$max_risk"
)
[ -n "$base_override" ] && resolver_args+=(--base "$base_override")
[ "$delegate_review" -eq 1 ] && resolver_args+=(--delegate-review)
[ "$may_merge" -eq 1 ] && resolver_args+=(--may-merge)
resolver_args+=(--json)

if ! scope_json="$(RUN_EPIC_SCOPE_RESOLVER_INTERNAL_ITEMS=1 "$RUN_EPIC_SCOPE_RESOLVER_CMD" "${resolver_args[@]}")"; then
  error_exit "underlying scope resolver failed for issue #$resolved_issue"
fi

out_json="$(printf '%s\n' "$scope_json" | jq -c \
  --arg itemInput "$item_input" \
  --argjson resolvedIssue "$resolved_issue" \
  '.scopeSource = "item" | .epicNumber = null | .itemInput = $itemInput | .resolvedIssueNumber = $resolvedIssue')"

if [ "$json_output" -eq 1 ]; then
  printf '%s\n' "$out_json"
  exit 0
fi

printf 'Run Item Scope Resolver\n'
printf 'Resolved issue: #%s\n' "$resolved_issue"
printf 'Item input: %s\n' "$item_input"
printf 'Base branch: %s (%s)\n' "$(printf '%s\n' "$out_json" | jq -r '.baseBranch // "ambiguous"')" "$(printf '%s\n' "$out_json" | jq -r '.baseReason')"
printf '%s\n' "$out_json" | jq -r '.groups.eligible[]? | "- eligible #\(.number) \(.title)"'
printf '%s\n' "$out_json" | jq -r '.groups.blocked[]? | "- blocked #\(.number) \(.title)"'
printf '%s\n' "$out_json" | jq -r '.groups.ambiguous[]? | "- ambiguous #\(.number) \(.title)"'
printf 'Read-only: %s\n' "$(printf '%s\n' "$out_json" | jq -r '.readOnlyGuarantee')"
