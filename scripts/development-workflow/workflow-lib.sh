#!/usr/bin/env bash

set -euo pipefail

workflow_script_dir() {
  CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
}

workflow_repo_root() {
  CDPATH= cd -- "$(workflow_script_dir)/../.." && pwd
}

workflow_config_file() {
  printf '%s/.ai-dev-workflow.yaml\n' "$(workflow_repo_root)"
}

workflow_config_exists() {
  [ -f "$(workflow_config_file)" ]
}

cd_workflow_repo_root() {
  cd -- "$(workflow_repo_root)"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

gh_available() {
  have_cmd gh && gh auth status >/dev/null 2>&1
}

require_gh() {
  if ! gh_available; then
    echo "GitHub CLI authentication is required for this script." >&2
    exit 2
  fi
}

repo_slug() {
  gh repo view --json nameWithOwner --jq '.nameWithOwner'
}

branch_prefix() {
  case "$1" in
    spec/*) printf 'spec\n' ;;
    implementation-plan/*) printf 'implementation-plan\n' ;;
    feature/*) printf 'feature\n' ;;
    refactor/*) printf 'refactor\n' ;;
    fix/*) printf 'fix\n' ;;
    hotfix/*) printf 'hotfix\n' ;;
    release/*) printf 'release\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

reviewer_for_branch() {
  case "$(branch_prefix "$1")" in
    spec) printf 'spec-reviewer\n' ;;
    implementation-plan) printf 'implementation-plan-reviewer\n' ;;
    feature|refactor|fix|hotfix) printf 'code-reviewer\n' ;;
    *) printf 'none\n' ;;
  esac
}

print_kv() {
  printf '%s=%s\n' "$1" "$2"
}

print_kv_escaped() {
  local value="$2"
  value="${value//\\/\\\\}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\t'/\\t}"
  printf '%s=%s\n' "$1" "$value"
}

soft_suggestion_prefixes() {
  cat <<'EOF'
Consider
You might
An alternative
Optionally
It could be cleaner to
Perhaps
Maybe
You could
One option is
Alternatively
EOF
}

is_soft_suggestion() {
  local body="$1"
  local line
  local prefix
  local normalized_line
  local saw_content=0
  local matched=0
  local in_code_block=0

  while IFS= read -r line; do
    normalized_line="${line%$'\r'}"
    normalized_line="${normalized_line#"${normalized_line%%[![:space:]]*}"}"
    normalized_line="${normalized_line#'**'}"
    normalized_line="${normalized_line%'**'}"
    [ -z "$normalized_line" ] && continue
    case "$normalized_line" in
      '```'*)
        in_code_block=$((1 - in_code_block))
        continue
        ;;
    esac
    [ "$in_code_block" -eq 1 ] && continue
    saw_content=1

    matched=0
    while IFS= read -r prefix; do
      [ -z "$prefix" ] && continue
      case "$normalized_line" in
        "$prefix"*) matched=1; break ;;
      esac
    done < <(soft_suggestion_prefixes)

    [ "$matched" -eq 0 ] && return 1
  done <<< "$body"

  [ "$saw_content" -eq 1 ]
}

open_pr_number_for_branch() {
  require_gh
  gh pr list --head "$1" --state open --json number --jq '.[0].number // empty'
}

workflow_config_review_platforms() {
  local config_file="${1:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  awk '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'"'"']|["'"'"']$/, "", value)
      return value
    }

    /^review:[[:space:]]*(#.*)?$/ {
      in_review = 1
      in_platforms = 0
      next
    }

    in_review && /^[^[:space:]#].*:[[:space:]]*$/ {
      in_review = 0
      in_platforms = 0
    }

    in_review && /^[[:space:]][[:space:]]platforms:[[:space:]]*(#.*)?$/ {
      in_platforms = 1
      next
    }

    in_review && in_platforms && /^[[:space:]][[:space:]][A-Za-z0-9_-]+:[[:space:]]*/ {
      in_platforms = 0
    }

    in_review && in_platforms && /^[[:space:]][[:space:]][[:space:]][[:space:]]-[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      print trim(line)
      next
    }

    in_review && in_platforms && !/^[[:space:]][[:space:]][[:space:]][[:space:]]-[[:space:]]*/ && !/^[[:space:]]*#/ && !/^[[:space:]]*$/ {
      in_platforms = 0
    }
  ' "$config_file"
}

workflow_config_provider() {
  local section="$1"
  local config_file="${2:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  awk -v section="$section" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'"'"']|["'"'"']$/, "", value)
      return value
    }

    $0 ~ ("^" section ":[[:space:]]*$") {
      in_section = 1
      next
    }

    in_section && /^[^[:space:]#].*:[[:space:]]*$/ {
      exit
    }

    in_section && /^[[:space:]][[:space:]]provider:[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*provider:[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      print trim(line)
      exit
    }
  ' "$config_file"
}

workflow_issue_tracker_provider_raw() {
  workflow_config_provider issue_tracker
}

workflow_normalize_issue_tracker_provider() {
  local raw="$1"
  printf '%s' "$raw" | tr '[:upper:]' '[:lower:]'
}

# Prints a coarse destination bucket for backlog creation: github | linear | other | none
# none: missing provider, none, or empty string
workflow_backlog_destination_kind() {
  local raw normalized
  raw="$(workflow_issue_tracker_provider_raw)"
  normalized="$(workflow_normalize_issue_tracker_provider "$raw")"
  if [ -z "$normalized" ] && [ -z "$raw" ]; then
    printf 'none\n'
    return 0
  fi
  case "$normalized" in
    ''|'none')
      printf 'none\n'
      ;;
    linear)
      printf 'linear\n'
      ;;
    github_issues|github-issues|github_projects|github-projects)
      printf 'github\n'
      ;;
    *)
      printf 'other\n'
      ;;
  esac
}

workflow_status_order() {
  case "$1" in
    Backlog) printf '0\n' ;;
    "Writing Spec") printf '1\n' ;;
    "Spec in Review") printf '2\n' ;;
    "Spec Ready") printf '3\n' ;;
    "Writing Plan") printf '4\n' ;;
    "Plan in Review") printf '5\n' ;;
    "Plan Ready") printf '6\n' ;;
    "In Development") printf '7\n' ;;
    "Development in Review") printf '8\n' ;;
    Merged) printf '9\n' ;;
    Released) printf '10\n' ;;
    *) printf -- '-1\n' ;;
  esac
}

# is_terminal_tracker_status <status>
#
# Returns 0 (true) if the status is a terminal state that means no further
# workflow work is needed: Released, Merged, or Cancelled.
# Returns 1 (false) for any other status (including empty/unknown).
is_terminal_tracker_status() {
  local status="$1"
  case "$status" in
    Released|Merged|Cancelled) return 0 ;;
    *) return 1 ;;
  esac
}

# Script-level cache for get_tracker_status_for_issue.
# Populated on the first call for a given owner+project pair; reused on all
# subsequent calls within the same script run — avoiding repeated full-board scans.
__workflow_tracker_cache_owner=""
__workflow_tracker_cache_project=""
__workflow_tracker_cache_json=""

# get_tracker_status_for_issue <issue_number>
#
# Queries GitHub Projects for the current Status of the given issue.
# Prints the status string (e.g. "Merged", "Released", "In Development").
# Prints an empty string when:
#   - GITHUB_PROJECT_NUMBER is unset (GitHub Projects not configured)
#   - The issue is not found in the project
#   - Any API call fails
# Returns 0 in all cases (non-blocking).
# Uses GITHUB_PROJECT_OWNER/GITHUB_PROJECT_NUMBER when set; owner falls back
# to the repository owner if omitted.
#
# The full project item list is fetched once per owner+project pair and cached
# in script-level variables to avoid a full-board scan on every call.
get_tracker_status_for_issue() {
  local issue_number="$1"
  local owner project_number item_json current_status

  owner="${GITHUB_PROJECT_OWNER:-$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || true)}"
  project_number="${GITHUB_PROJECT_NUMBER:-}"
  if [ -z "$owner" ] || [ -z "$project_number" ]; then
    printf ''
    return 0
  fi

  # Populate cache on first call or when owner/project changes.
  if [ "$__workflow_tracker_cache_owner" != "$owner" ] || \
     [ "$__workflow_tracker_cache_project" != "$project_number" ] || \
     [ -z "$__workflow_tracker_cache_json" ]; then
    __workflow_tracker_cache_json="$(gh project item-list "$project_number" --owner "$owner" --limit 10000 --format json 2>/dev/null || true)"
    __workflow_tracker_cache_owner="$owner"
    __workflow_tracker_cache_project="$project_number"
  fi

  item_json=$(printf '%s' "$__workflow_tracker_cache_json" \
    | jq -c --argjson num "$issue_number" '.items[] | select(.content.number == $num)' 2>/dev/null || true)
  if [ -z "$item_json" ]; then
    printf ''
    return 0
  fi

  current_status=$(printf '%s' "$item_json" | jq -r '.status // empty' 2>/dev/null || true)
  printf '%s' "${current_status:-}"
}

# update_tracker_status_best_effort <issue_number> <status_label> [required_current_status]
#
# Best-effort update for GitHub Projects Status field.
# - Returns 0 in all warning/failure cases to avoid blocking caller flows.
# - Respects status progression ordering and never rolls status backward.
# - Uses GITHUB_PROJECT_OWNER/GITHUB_PROJECT_NUMBER when set; owner falls back
#   to the repository owner if omitted.
update_tracker_status_best_effort() {
  local issue_number="$1"
  local status_label="$2"
  local required_current_status="${3:-}"
  local owner project_number project_id field_json field_id option_id item_json item_id current_status
  local target_order current_order

  owner="${GITHUB_PROJECT_OWNER:-$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || true)}"
  project_number="${GITHUB_PROJECT_NUMBER:-}"
  if [ -z "$owner" ] || [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_OWNER or GITHUB_PROJECT_NUMBER not set; skipping tracker status update."
    return 0
  fi

  project_id=$(gh project view "$project_number" --owner "$owner" --format json 2>/dev/null | jq -r '.id // empty' || true)
  if [ -z "$project_id" ]; then
    echo "Warning: could not resolve project ID for project #${project_number}; skipping tracker status update."
    return 0
  fi

  field_json=$(gh project field-list "$project_number" --owner "$owner" --format json 2>/dev/null || true)
  field_id=$(printf '%s' "$field_json" | jq -r '.fields[] | select(.name == "Status") | .id // empty' || true)
  option_id=$(printf '%s' "$field_json" | jq -r --arg label "$status_label" '.fields[] | select(.name == "Status") | .options[] | select(.name == $label) | .id // empty' || true)
  if [ -z "$field_id" ] || [ -z "$option_id" ]; then
    echo "Warning: could not resolve Status field or option '${status_label}'; skipping tracker status update."
    return 0
  fi

  item_json=$(gh project item-list "$project_number" --owner "$owner" --limit 10000 --format json 2>/dev/null \
    | jq -c --argjson num "$issue_number" '.items[] | select(.content.number == $num)' || true)
  item_id=$(printf '%s' "$item_json" | jq -r '.id // empty' || true)
  if [ -z "$item_id" ]; then
    echo "Warning: issue #${issue_number} not found in project #${project_number}; skipping tracker status update."
    return 0
  fi

  current_status=$(printf '%s' "$item_json" | jq -r '.status // empty' || true)
  if [ -n "$required_current_status" ] && [ "$current_status" != "$required_current_status" ]; then
    echo "Issue #${issue_number} current status '${current_status:-unknown}' does not match required source status '${required_current_status}'; skipping update."
    return 0
  fi
  target_order="$(workflow_status_order "$status_label")"
  current_order="$(workflow_status_order "$current_status")"
  if [ -n "$current_status" ] && [ "$current_order" -eq -1 ] && [ -z "$required_current_status" ]; then
    echo "Warning: Issue #${issue_number} current status '${current_status}' is unrecognized; skipping update to '${status_label}' to avoid silent state corruption. Provide required_current_status to proceed anyway."
    return 0
  fi
  if [ "$target_order" -ge 0 ] && [ "$current_order" -gt "$target_order" ]; then
    echo "Issue #${issue_number} is already at status '${current_status}' (more advanced than '${status_label}'); skipping rollback."
    return 0
  fi

  echo "Updating tracker status for issue #${issue_number} to '${status_label}'..."
  gh api graphql -f query="
    mutation {
      updateProjectV2ItemFieldValue(input: {
        projectId: \"${project_id}\"
        itemId: \"${item_id}\"
        fieldId: \"${field_id}\"
        value: { singleSelectOptionId: \"${option_id}\" }
      }) {
        projectV2Item { id }
      }
    }
  " 2>/dev/null || echo "Warning: GraphQL mutation failed for issue #${issue_number}; tracker status not updated."
}
