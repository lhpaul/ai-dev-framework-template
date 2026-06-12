#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-epic-scope-resolver.sh --epic <issue-number> [--base <branch>] [--json]
  ./scripts/development-workflow/run-epic-scope-resolver.sh --items <issue-number>[,<issue-number>...] [--base <branch>] [--json]

Resolves a delegated epic or explicit item list into a read-only execution set.
The resolver never starts backlog items, updates tracker status, creates
branches, opens PRs, merges PRs, closes issues, or deletes branches.
EOF
}

json_output=0
epic_number=""
items_arg=""
base_override=""

error_exit() {
  echo "ERROR: $*" >&2
  exit 1
}

require_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
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

while [ "$#" -gt 0 ]; do
  case "$1" in
    --epic)
      require_value "$@"
      epic_number="$2"
      shift 2
      ;;
    --items)
      require_value "$@"
      items_arg="$2"
      shift 2
      ;;
    --base)
      require_value "$@"
      base_override="$2"
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

if [ -n "$epic_number" ] && [ -n "$items_arg" ]; then
  echo "ERROR: pass exactly one of --epic or --items, not both." >&2
  exit 64
fi
if [ -z "$epic_number" ] && [ -z "$items_arg" ]; then
  echo "ERROR: pass exactly one of --epic or --items." >&2
  exit 64
fi
if [ -n "$epic_number" ] && ! is_positive_int "$epic_number"; then
  echo "ERROR: --epic must be a positive integer." >&2
  exit 64
fi

require_gh

repo="$(repo_slug)"
owner="${repo%%/*}"
repo_name="${repo#*/}"

tmp_dir="$(mktemp -d)"
items_file="$tmp_dir/items.jsonl"
subissues_file="$tmp_dir/subissues.jsonl"
touch "$items_file" "$subissues_file"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

add_unique_item() {
  local issue_number="$1"
  if ! is_positive_int "$issue_number"; then
    echo "ERROR: item '${issue_number}' is not a positive integer." >&2
    exit 64
  fi
  if ! grep -qx "$issue_number" "$subissues_file" 2>/dev/null; then
    printf '%s\n' "$issue_number" >> "$subissues_file"
  fi
}

parse_explicit_items() {
  local raw="$1"
  local remaining="${raw},"
  local part trimmed

  while [ -n "$remaining" ]; do
    part="${remaining%%,*}"
    remaining="${remaining#*,}"
    trimmed="$(printf '%s' "$part" | tr -d '[:space:]')"
    if [ -z "$trimmed" ]; then
      echo "ERROR: --items contains an empty item." >&2
      exit 64
    fi
    add_unique_item "$trimmed"
  done
}

query_epic_subissues() {
  local after=""
  local has_next="true"
  local response
  local -a graphql_args

  while [ "$has_next" = "true" ]; do
    graphql_args=(
      gh api graphql
      -F owner="$owner"
      -F repo="$repo_name"
      -F number="$epic_number"
    )
    if [ -n "$after" ]; then
      graphql_args+=(-f after="$after")
      graphql_args+=(
        -f query='
        query($owner: String!, $repo: String!, $number: Int!, $after: String) {
          repository(owner: $owner, name: $repo) {
            issue(number: $number) {
              number
              title
              subIssues(first: 100, after: $after) {
                nodes { number title state }
                pageInfo { hasNextPage endCursor }
              }
            }
          }
        }
      '
      )
    else
      graphql_args+=(
        -f query='
        query($owner: String!, $repo: String!, $number: Int!) {
          repository(owner: $owner, name: $repo) {
            issue(number: $number) {
              number
              title
              subIssues(first: 100) {
                nodes { number title state }
                pageInfo { hasNextPage endCursor }
              }
            }
          }
        }
      '
      )
    fi

    if ! response="$("${graphql_args[@]}" 2>/dev/null)"; then
      error_exit "failed to read native sub-issues for epic #${epic_number}."
    fi

    if [ -z "$response" ]; then
      error_exit "empty GraphQL response while reading epic #${epic_number}."
    fi

    if ! printf '%s\n' "$response" | jq -e '.data.repository.issue != null' >/dev/null; then
      error_exit "epic issue #${epic_number} not found or inaccessible."
    fi

    printf '%s\n' "$response" | jq -r '.data.repository.issue.subIssues.nodes[]?.number' \
      >> "$subissues_file" || {
        error_exit "failed to parse sub-issues for epic #${epic_number}."
      }

    if ! has_next="$(printf '%s\n' "$response" | jq -r '.data.repository.issue.subIssues.pageInfo.hasNextPage // false')"; then
      error_exit "failed to parse sub-issue pagination for epic #${epic_number}."
    fi
    if ! after="$(printf '%s\n' "$response" | jq -r '.data.repository.issue.subIssues.pageInfo.endCursor // ""')"; then
      error_exit "failed to parse sub-issue cursor for epic #${epic_number}."
    fi
  done

  sort -n -u "$subissues_file" -o "$subissues_file"

  if [ ! -s "$subissues_file" ]; then
    printf 'EMPTY_EPIC_SCOPE=1\n' > "$tmp_dir/empty_scope"
  fi
}

verify_parent() {
  local child="$1"
  local response parent

  if ! response="$(gh api graphql \
    -F owner="$owner" \
    -F repo="$repo_name" \
    -F number="$child" \
    -f query='
      query($owner: String!, $repo: String!, $number: Int!) {
        repository(owner: $owner, name: $repo) {
          issue(number: $number) {
            number
            parent { number title }
          }
        }
      }
    ' 2>/dev/null)"; then
    error_exit "failed to verify parent relationship for issue #${child}."
  fi
  if ! parent="$(printf '%s\n' "$response" | jq -r '.data.repository.issue.parent.number // empty')"; then
    error_exit "failed to parse parent relationship for issue #${child}."
  fi
  if [ "$parent" != "$epic_number" ]; then
    error_exit "issue #${child} does not point back to epic #${epic_number}."
  fi
}

completed_status() {
  case "$1" in
    Done|Merged|Released) return 0 ;;
    *) return 1 ;;
  esac
}

labels_csv() {
  jq -r '[.labels[].name] | join(",")'
}

integration_label_for_issue_json() {
  jq -r '[.labels[].name | select(startswith("integration-branch:"))] | first // ""'
}

linked_pr_json() {
  local issue="$1"
  local open_raw open_prs merged_raw merged_prs open_count merged_count
  local pr_list_limit=5000

  if ! open_raw="$(gh pr list --state open --limit "$pr_list_limit" \
    --json number,title,headRefName,baseRefName,isDraft,labels 2>/dev/null)"; then
    error_exit "failed to read open PRs while resolving issue #${issue}."
  fi
  if ! open_count="$(printf '%s\n' "$open_raw" | jq 'length')"; then
    error_exit "failed to parse open PR count while resolving issue #${issue}."
  fi
  if [ "$open_count" -ge "$pr_list_limit" ]; then
    error_exit "open PR list reached ${pr_list_limit}; rerun with a narrower repository state before resolving issue #${issue}."
  fi
  if ! open_prs="$(printf '%s\n' "$open_raw" | jq --arg issue "$issue" '
        [ .[]
          | select(.headRefName | test("^(spec|implementation-plan|feature|fix|refactor|hotfix)/" + $issue + "(-|$)"))
          | {
              number,
              title,
              state: "OPEN",
              headRefName,
              baseRefName,
              isDraft,
              labels: [.labels[].name]
            }
        ]')"; then
    error_exit "failed to parse open PRs while resolving issue #${issue}."
  fi

  if ! merged_raw="$(gh pr list --state merged --limit "$pr_list_limit" \
    --json number,title,headRefName,baseRefName,mergedAt 2>/dev/null)"; then
    error_exit "failed to read merged PRs while resolving issue #${issue}."
  fi
  if ! merged_count="$(printf '%s\n' "$merged_raw" | jq 'length')"; then
    error_exit "failed to parse merged PR count while resolving issue #${issue}."
  fi
  if [ "$merged_count" -ge "$pr_list_limit" ]; then
    error_exit "merged PR list reached ${pr_list_limit}; rerun with a narrower repository state before resolving issue #${issue}."
  fi
  if ! merged_prs="$(printf '%s\n' "$merged_raw" | jq --arg issue "$issue" '
        [ .[]
          | select(.headRefName | test("^(spec|implementation-plan|feature|fix|refactor|hotfix)/" + $issue + "(-|$)"))
          | {
              number,
              title,
              state: "MERGED",
              headRefName,
              baseRefName,
              isDraft: false,
              labels: [],
              mergedAt
            }
        ]')"; then
    error_exit "failed to parse merged PRs while resolving issue #${issue}."
  fi

  jq -n --argjson open "$open_prs" --argjson merged "$merged_prs" \
    '{open: $open, merged: $merged}'
}

dependency_json() {
  local body="$1"
  local deps dep state title
  deps="$(
    printf '%s\n' "$body" |
      awk '
        {
          line = tolower($0)
          while (match(line, /(depends on|blocked by|requires|waiting on) #[0-9]+/)) {
            token = substr(line, RSTART, RLENGTH)
            sub(/^.*#/, "", token)
            print token
            line = substr(line, RSTART + RLENGTH)
          }
        }
      ' |
      sort -n -u
  )"
  if [ -z "$deps" ]; then
    jq -n '{state:"none", issues:[]}'
    return 0
  fi

  local dep_file="$tmp_dir/deps.jsonl"
  : > "$dep_file"
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    if ! dep_view="$(gh issue view "$dep" --json number,title,state 2>/dev/null)"; then
      error_exit "failed to read dependency issue #${dep}."
    fi
    if ! state="$(printf '%s\n' "$dep_view" | jq -r '.state')"; then
      error_exit "failed to parse dependency issue #${dep} state."
    fi
    if ! title="$(printf '%s\n' "$dep_view" | jq -r '.title')"; then
      error_exit "failed to parse dependency issue #${dep} title."
    fi
    jq -n --argjson number "$dep" --arg title "$title" --arg state "$state" \
      '{number:$number,title:$title,state:$state}' >> "$dep_file"
  done <<< "$deps"

  jq -s '
    {
      state: (if any(.[]; .state != "CLOSED") then "blocked" else "satisfied" end),
      issues: .
    }
  ' "$dep_file"
}

enrich_item() {
  local issue="$1"
  local issue_json title state state_reason labels integration_label status type priority pr_json dep_json group body
  local merged_impl_count open_review_count dep_state ambiguity_reason

  if ! issue_json="$(gh issue view "$issue" --json number,title,state,stateReason,body,labels,projectItems 2>/dev/null)"; then
    jq -n --argjson number "$issue" '{number:$number,title:"",state:"UNKNOWN",group:"ambiguous",ambiguityReason:"issue could not be read"}'
    return 0
  fi

  if ! title="$(printf '%s\n' "$issue_json" | jq -r '.title')"; then
    error_exit "failed to parse issue #${issue} title."
  fi
  if ! state="$(printf '%s\n' "$issue_json" | jq -r '.state')"; then
    error_exit "failed to parse issue #${issue} state."
  fi
  if ! state_reason="$(printf '%s\n' "$issue_json" | jq -r '.stateReason // ""')"; then
    error_exit "failed to parse issue #${issue} state reason."
  fi
  if ! body="$(printf '%s\n' "$issue_json" | jq -r '.body // ""')"; then
    error_exit "failed to parse issue #${issue} body."
  fi
  if ! labels="$(printf '%s\n' "$issue_json" | labels_csv)"; then
    error_exit "failed to parse issue #${issue} labels."
  fi
  if ! integration_label="$(printf '%s\n' "$issue_json" | integration_label_for_issue_json)"; then
    error_exit "failed to parse issue #${issue} integration branch label."
  fi
  if ! status="$(get_tracker_status_for_issue "$issue" 2>/dev/null)"; then
    error_exit "failed to read tracker status for issue #${issue}."
  fi
  if ! type="$(get_tracker_type_for_issue "$issue" 2>/dev/null)"; then
    error_exit "failed to read tracker type for issue #${issue}."
  fi
  if ! priority="$(printf '%s\n' "$issue_json" | jq -r '.projectItems[0].priority.name // .projectItems[0].priority // ""')"; then
    error_exit "failed to parse issue #${issue} priority."
  fi
  pr_json="$(linked_pr_json "$issue")"
  dep_json="$(dependency_json "$body")"
  if ! merged_impl_count="$(printf '%s\n' "$pr_json" | jq '[.merged[] | select(.headRefName | test("^(feature|fix|refactor|hotfix)/"))] | length')"; then
    error_exit "failed to parse merged PR state for issue #${issue}."
  fi
  if ! open_review_count="$(printf '%s\n' "$pr_json" | jq '[.open[] | select(.labels | index("ready-for-human-review"))] | length')"; then
    error_exit "failed to parse open PR state for issue #${issue}."
  fi
  if ! dep_state="$(printf '%s\n' "$dep_json" | jq -r '.state')"; then
    error_exit "failed to parse dependency state for issue #${issue}."
  fi

  group="eligible"
  ambiguity_reason=""
  if completed_status "$status" || [ "$state_reason" = "COMPLETED" ] \
    || [ "$merged_impl_count" -gt 0 ]; then
    group="already_merged"
  elif [ "$status" = "Cancelled" ] || { [ "$state" = "CLOSED" ] && [ "$state_reason" != "COMPLETED" ]; }; then
    group="ambiguous"
    ambiguity_reason="issue closed or cancelled without completed state"
  elif [ "$open_review_count" -gt 0 ] \
    || [ "$status" = "Spec in Review" ] \
    || [ "$status" = "Plan in Review" ] \
    || [ "$status" = "Development in Review" ]; then
    group="in_review"
  elif [ "$dep_state" = "blocked" ]; then
    group="blocked"
  fi

  jq -n \
    --argjson number "$issue" \
    --arg title "$title" \
    --arg state "$state" \
    --arg stateReason "$state_reason" \
    --arg labels "$labels" \
    --arg integrationLabel "$integration_label" \
    --arg status "$status" \
    --arg type "$type" \
    --arg priority "$priority" \
    --argjson prs "$pr_json" \
    --argjson dependencies "$dep_json" \
    --arg group "$group" \
    --arg ambiguityReason "$ambiguity_reason" \
    '{
      number: $number,
      title: $title,
      issueState: $state,
      issueStateReason: $stateReason,
      labels: (if $labels == "" then [] else ($labels | split(",")) end),
      integrationBranchLabel: $integrationLabel,
      status: $status,
      type: $type,
      priority: $priority,
      dependencies: $dependencies,
      pullRequests: $prs,
      group: $group,
      ambiguityReason: (if $ambiguityReason == "" then null else $ambiguityReason end)
    }'
}

if [ -n "$epic_number" ]; then
  query_epic_subissues
  if [ -s "$subissues_file" ]; then
    while IFS= read -r child; do
      verify_parent "$child"
    done < "$subissues_file"
  fi
else
  parse_explicit_items "$items_arg"
fi

while IFS= read -r issue; do
  [ -n "$issue" ] || continue
  enrich_item "$issue" >> "$items_file"
done < "$subissues_file"

items_json="$(jq -s '.' "$items_file")"

integration_labels="$(printf '%s\n' "$items_json" | jq -r '[.[].integrationBranchLabel | select(. != "")] | unique | .[]')"
integration_count="$(printf '%s\n' "$integration_labels" | sed '/^$/d' | wc -l | tr -d ' ')"

base_branch=""
base_reason=""
set_ambiguous=0
if [ -n "$base_override" ]; then
  base_branch="$base_override"
  base_reason="supplied --base override"
elif [ "$integration_count" -eq 1 ]; then
  label="$(printf '%s\n' "$integration_labels" | sed -n '1p')"
  base_branch="develop-${label#integration-branch:}"
  base_reason="shared integration branch label ${label}"
elif [ "$integration_count" -gt 1 ]; then
  base_branch=""
  base_reason="conflicting integration branch labels"
  set_ambiguous=1
else
  base_branch="develop"
  base_reason="no integration branch label"
fi

if [ "$set_ambiguous" -eq 1 ]; then
  items_json="$(printf '%s\n' "$items_json" | jq 'map(.group = "ambiguous" | .ambiguityReason = "conflicting integration branch labels")')"
fi

empty_epic=0
[ -f "$tmp_dir/empty_scope" ] && empty_epic=1

summary_json="$(jq -n \
  --arg scopeSource "$([ -n "$epic_number" ] && printf 'epic' || printf 'items')" \
  --arg epicNumber "$epic_number" \
  --arg itemInput "$items_arg" \
  --arg baseBranch "$base_branch" \
  --arg baseReason "$base_reason" \
  --argjson items "$items_json" \
  --argjson emptyEpic "$empty_epic" \
  '{
    scopeSource: $scopeSource,
    epicNumber: (if $epicNumber == "" then null else ($epicNumber | tonumber) end),
    itemInput: $itemInput,
    baseBranch: $baseBranch,
    baseReason: $baseReason,
    emptyEpicScope: ($emptyEpic == 1),
    readOnlyGuarantee: "No tracker status, branch, PR, merge, issue-close, or cleanup mutation was performed.",
    groups: {
      eligible: [$items[] | select(.group == "eligible")],
      blocked: [$items[] | select(.group == "blocked")],
      already_merged: [$items[] | select(.group == "already_merged")],
      in_review: [$items[] | select(.group == "in_review")],
      ambiguous: [$items[] | select(.group == "ambiguous")],
      out_of_scope: [$items[] | select(.group == "out_of_scope")]
    },
    items: $items
  }')"

if [ "$json_output" -eq 1 ]; then
  printf '%s\n' "$summary_json"
  exit 0
fi

printf 'Run Epic Scope Resolver\n'
printf 'Scope source: %s\n' "$(printf '%s\n' "$summary_json" | jq -r '.scopeSource')"
if [ -n "$epic_number" ]; then
  printf 'Epic: #%s\n' "$epic_number"
fi
if [ "$(printf '%s\n' "$summary_json" | jq -r '.emptyEpicScope')" = "true" ]; then
  printf 'Native sub-issues: none resolved for epic #%s\n' "$epic_number"
fi
printf 'Base branch: %s (%s)\n' "${base_branch:-ambiguous}" "$base_reason"
printf 'Read-only: %s\n\n' "$(printf '%s\n' "$summary_json" | jq -r '.readOnlyGuarantee')"

for group in eligible blocked already_merged in_review ambiguous out_of_scope; do
  count="$(printf '%s\n' "$summary_json" | jq ".groups.${group} | length")"
  printf '%s (%s)\n' "$group" "$count"
  printf '%s\n' "$summary_json" | jq -r ".groups.${group}[] | \"- #\\(.number) \\(.title) [status=\\(.status // \"\"), type=\\(.type // \"\"), state=\\(.issueState)]\""
done
