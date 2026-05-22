#!/usr/bin/env bash

set -euo pipefail

workflow_script_dir() {
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
}

workflow_repo_root() {
  CDPATH='' cd -- "$(workflow_script_dir)/../.." && pwd
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

workflow_config_review_phase_after_clean_platforms() {
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
      in_phase = 0
      next
    }

    in_review && /^[^[:space:]#].*:[[:space:]]*$/ {
      in_review = 0
      in_phase = 0
    }

    in_review && /^[[:space:]][[:space:]]phase_after_clean:[[:space:]]*(#.*)?$/ {
      in_phase = 1
      next
    }

    in_review && in_phase && /^[[:space:]][[:space:]][A-Za-z0-9_-]+:[[:space:]]*/ {
      in_phase = 0
    }

    in_review && in_phase && /^[[:space:]][[:space:]][[:space:]][[:space:]]-[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      print trim(line)
      next
    }

    in_review && in_phase && !/^[[:space:]][[:space:]][[:space:]][[:space:]]-[[:space:]]*/ && !/^[[:space:]]*#/ && !/^[[:space:]]*$/ {
      in_phase = 0
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

workflow_config_field() {
  local section="$1"
  local field="$2"
  local config_file="${3:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  awk -v section="$section" -v field="$field" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'"'"']|["'"'"']$/, "", value)
      return value
    }

    $0 ~ ("^" section ":[[:space:]]*$") {
      in_section = 1
      next
    }

    in_section && /^[^[:space:]#].*:[[:space:]]*/ {
      exit
    }

    in_section {
      # Match "  <field>: <value>" — two-space indent, exact field name, optional comment
      pattern = "^[[:space:]][[:space:]]" field ":[[:space:]]*"
      if ($0 ~ pattern) {
        line = $0
        sub(/^[[:space:]]*[^[:space:]]*:[[:space:]]*/, "", line)
        sub(/[[:space:]]+#.*$/, "", line)
        print trim(line)
        exit
      }
    }
  ' "$config_file"
}

workflow_issue_tracker_project_number() {
  workflow_config_field issue_tracker project_number
}

# workflow_resolve_github_project_owner
#
# Resolves the GitHub project owner through a tiered fallback chain.
# Prints the resolved owner name, or an empty string when all tiers fail.
# Returns 0 in all cases (non-blocking).
#
# Resolution order:
#   1. GITHUB_PROJECT_OWNER env var (fastest; always preferred)
#   2. gh repo view API call
#   3. Parse owner from git remote get-url origin (SSH or HTTPS format)
#
# Rationale for Tier 3: when workflow-lib.sh is sourced directly in a
# subagent shell (not invoked via a wrapper script), GITHUB_TOKEN may be
# absent and gh repo view fails silently. The git remote URL is available
# in any cloned repository regardless of gh authentication state.
#
# Emits a warning to stderr only when all three tiers fail, so callers can
# surface the failure visibly rather than silently skipping tracker updates.
workflow_resolve_github_project_owner() {
  # Tier 1: explicit env var
  if [ -n "${GITHUB_PROJECT_OWNER:-}" ]; then
    printf '%s' "$GITHUB_PROJECT_OWNER"
    return 0
  fi

  # Tier 2: gh repo view API
  local owner
  owner="$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || true)"
  if [ -n "$owner" ]; then
    printf '%s' "$owner"
    return 0
  fi

  # Tier 3: parse owner from git remote URL
  # Supports common GitHub remote URL formats:
  #   HTTPS:             https://github.com/owner/repo.git
  #   Credentialed HTTPS: https://user@github.com/owner/repo.git
  #   SCP-style SSH:     git@github.com:owner/repo.git
  #   SSH URL:           ssh://git@github.com/owner/repo.git
  local remote_url
  remote_url="$(git remote get-url origin 2>/dev/null || true)"
  if [ -n "$remote_url" ]; then
    case "$remote_url" in
      https://*github.com/*)
        # Strip protocol and optional user@ prefix, then extract owner segment
        owner="${remote_url#https://}"
        owner="${owner#*@}"          # remove optional user@ for credentialed HTTPS
        owner="${owner#github.com/}" # remove host
        owner="${owner%%/*}"
        ;;
      git@github.com:*)
        owner="${remote_url#git@github.com:}"
        owner="${owner%%/*}"
        ;;
      ssh://git@github.com/*)
        owner="${remote_url#ssh://git@github.com/}"
        owner="${owner%%/*}"
        ;;
    esac
    if [ -n "$owner" ]; then
      printf '%s' "$owner"
      return 0
    fi
  fi

  # All tiers failed — emit a visible warning so the caller knows why the
  # tracker update was skipped, rather than silently swallowing the failure.
  echo "Warning: could not resolve GITHUB_PROJECT_OWNER from env var, 'gh repo view', or git remote URL. Set GITHUB_PROJECT_OWNER to enable tracker status updates." >&2
  printf ''
  return 0
}

# workflow_issue_tracker_custom_field <key> [config_file]
#
# Reads issue_tracker.custom_fields.<key> from .ai-dev-workflow.yaml.
# Prints the value, or empty string when:
#   - The config file is absent
#   - The custom_fields subsection is absent
#   - The key is absent within custom_fields
# Returns 0 in all cases (non-blocking).
workflow_issue_tracker_custom_field() {
  local key="$1"
  local config_file="${2:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  awk -v key="$key" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'"'"']|["'"'"']$/, "", value)
      return value
    }

    /^issue_tracker:[[:space:]]*(#.*)?$/ {
      in_section = 1
      in_custom = 0
      next
    }

    in_section && /^[^[:space:]#]/ {
      in_section = 0
      in_custom = 0
    }

    in_section && /^[[:space:]][[:space:]]custom_fields:[[:space:]]*(#.*)?$/ {
      in_custom = 1
      next
    }

    in_section && in_custom && /^[[:space:]][[:space:]][A-Za-z0-9_-]/ {
      if ($0 !~ /^[[:space:]][[:space:]][[:space:]][[:space:]]/) {
        in_custom = 0
      }
    }

    in_section && in_custom && /^[[:space:]][[:space:]][[:space:]][[:space:]]/ {
      pattern = "^[[:space:]][[:space:]][[:space:]][[:space:]]" key ":[[:space:]]*"
      if ($0 ~ pattern) {
        line = $0
        sub(/^[[:space:]]*[^[:space:]]*:[[:space:]]*/, "", line)
        sub(/[[:space:]]+#.*$/, "", line)
        print trim(line)
        exit
      }
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
# Queries the configured issue tracker for the current Status of the given issue.
# Prints the status string (e.g. "Merged", "Released", "In Development").
# Prints an empty string when:
#   - provider is 'linear' (Linear status reads require MCP/API; not available in shell)
#   - project_number is unset in both GITHUB_PROJECT_NUMBER and .ai-dev-workflow.yaml
#   - The issue is not found in the project
#   - Any API call fails
# Returns 0 in all cases (non-blocking).
# Owner is resolved via workflow_resolve_github_project_owner (see that function
# for the tiered fallback chain: env var → gh repo view → git remote URL).
# project_number falls back to issue_tracker.project_number in .ai-dev-workflow.yaml.
#
# The full project item list is fetched once per owner+project pair and cached
# in script-level variables to avoid a full-board scan on every call.
get_tracker_status_for_issue() {
  local issue_number="$1"
  local owner project_number item_json current_status

  # Provider routing: Linear status reads require MCP/API and cannot be
  # performed by this shell function. Return empty (caller treats as unknown).
  local _gts_provider
  _gts_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$_gts_provider" = "linear" ]; then
    printf ''
    return 0
  fi

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    printf ''
    return 0
  fi
  owner="$(workflow_resolve_github_project_owner)"
  if [ -z "$owner" ]; then
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

  # Use Python3 to parse the JSON to handle issue bodies that contain literal
  # control characters (U+0000–U+001F), which cause jq parse errors (#375).
  # strict=False allows Python3's json decoder to accept unescaped control chars.
  # issue_number is passed via sys.argv[1] (not interpolated into source code) to
  # avoid shell-variable-into-Python-source injection.
  item_json=$(printf '%s' "$__workflow_tracker_cache_json" \
    | python3 -c "
import json, sys
num = int(sys.argv[1])
data = json.loads(sys.stdin.read(), strict=False)
for item in data.get('items', []):
    if item.get('content', {}).get('number') == num:
        print(json.dumps(item))
        break
" "$issue_number" 2>/dev/null || true)
  if [ -z "$item_json" ]; then
    printf ''
    return 0
  fi

  current_status=$(printf '%s' "$item_json" | python3 -c "
import json, sys
item = json.loads(sys.stdin.read(), strict=False)
print(item.get('status') or '', end='')
" 2>/dev/null || true)
  printf '%s' "${current_status:-}"
}

# ensure_on_project_board <issue_number> <initial_status>
#
# Idempotently ensures a GitHub issue is registered on the configured project board.
# - If the issue is already on the board, logs "already present" and returns 0.
# - If the issue is not on the board, adds it and sets its status to <initial_status>.
# - On any API or permissions failure, logs a warning and returns 0 (fail-open).
# - Must be called before update_tracker_status_best_effort in each agent completion
#   sequence so that the issue is board-registered before a status update is attempted.
ensure_on_project_board() {
  local issue_number="$1"
  local initial_status="$2"
  local owner project_number item_json repo_url

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_NUMBER not set and no project_number in .ai-dev-workflow.yaml; skipping board-membership check for issue #${issue_number}."
    return 0
  fi
  owner="$(workflow_resolve_github_project_owner)"
  if [ -z "$owner" ]; then
    # workflow_resolve_github_project_owner already emitted a warning.
    return 0
  fi

  # Check whether issue is already on the board using Python3 for control-character
  # robustness (same pattern as update_tracker_status_best_effort).
  item_json=$(gh project item-list "$project_number" --owner "$owner" --limit 10000 --format json 2>/dev/null \
    | python3 -c "
import json, sys
num = int(sys.argv[1])
data = json.loads(sys.stdin.read(), strict=False)
for item in data.get('items', []):
    if item.get('content', {}).get('number') == num:
        print(json.dumps(item))
        break
" "$issue_number" || true)

  if [ -n "$item_json" ]; then
    echo "Board membership check: issue #${issue_number} already on project board."
    return 0
  fi

  # Issue is not on the board — add it.
  repo_url=$(gh repo view --json url --jq '.url' 2>/dev/null || true)
  if [ -z "$repo_url" ]; then
    echo "Warning: could not resolve repo URL; skipping board-add for issue #${issue_number}."
    return 0
  fi
  gh project item-add "$project_number" --owner "$owner" \
    --url "${repo_url}/issues/${issue_number}" 2>/dev/null \
    || { echo "Warning: gh project item-add failed for issue #${issue_number}; continuing."; return 0; }

  echo "Board membership check: issue #${issue_number} added to project board."

  # Set initial status for the newly added item.
  update_tracker_status_best_effort "$issue_number" "$initial_status"
}

# update_tracker_status_best_effort <issue_number> <status_label> [required_current_status]
#
# Best-effort update for the configured issue tracker's Status field.
# Supports GitHub Projects (provider: github_projects) and emits actionable
# guidance for Linear (provider: linear), which requires MCP/API access.
# - Returns 0 in all warning/failure cases to avoid blocking caller flows.
# - Respects status progression ordering and never rolls status backward
#   (GitHub Projects path only; ordering is not enforced for Linear).
# - Owner is resolved via workflow_resolve_github_project_owner (see that function
#   for the tiered fallback chain: env var → gh repo view → git remote URL).
# - project_number falls back to issue_tracker.project_number in .ai-dev-workflow.yaml.
update_tracker_status_best_effort() {
  local issue_number="$1"
  local status_label="$2"
  local required_current_status="${3:-}"
  local owner project_number project_id field_json field_id option_id item_json item_id current_status
  local target_order current_order

  # Provider routing: Linear status updates require MCP/API and cannot be
  # performed automatically by this shell function. Emit a clear, actionable
  # message so callers (and operators) know what manual step is needed.
  local _utsbe_provider
  _utsbe_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$_utsbe_provider" = "linear" ]; then
    echo "Warning: Linear tracker detected — cannot update issue #${issue_number} status to '${status_label}' automatically. Use the Linear MCP server or API to transition this issue to '${status_label}'. See docs/workflow/development-workflow/integrations/linear.md for details."
    return 0
  fi

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_NUMBER not set and no project_number in .ai-dev-workflow.yaml; skipping tracker status update."
    return 0
  fi
  owner="$(workflow_resolve_github_project_owner)"
  if [ -z "$owner" ]; then
    # workflow_resolve_github_project_owner already emitted a warning.
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

  # Use Python3 to parse the JSON to handle issue bodies that contain literal
  # control characters (U+0000–U+001F), which cause jq parse errors (#375).
  # strict=False allows Python3's json decoder to accept unescaped control chars.
  # issue_number is passed via sys.argv[1] (not interpolated into source code) to
  # avoid shell-variable-into-Python-source injection.
  item_json=$(gh project item-list "$project_number" --owner "$owner" --limit 10000 --format json 2>/dev/null \
    | python3 -c "
import json, sys
num = int(sys.argv[1])
data = json.loads(sys.stdin.read(), strict=False)
for item in data.get('items', []):
    if item.get('content', {}).get('number') == num:
        print(json.dumps(item))
        break
" "$issue_number" || true)
  item_id=$(printf '%s' "$item_json" | python3 -c "
import json, sys
item = json.loads(sys.stdin.read(), strict=False)
print(item.get('id') or '', end='')
" 2>/dev/null || true)
  if [ -z "$item_id" ]; then
    echo "Warning: issue #${issue_number} not found in project #${project_number}; skipping tracker status update."
    return 0
  fi

  current_status=$(printf '%s' "$item_json" | python3 -c "
import json, sys
item = json.loads(sys.stdin.read(), strict=False)
print(item.get('status') or '', end='')
" 2>/dev/null || true)
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
  gh api graphql \
    -f projectId="$project_id" \
    -f itemId="$item_id" \
    -f fieldId="$field_id" \
    -f optionId="$option_id" \
    -f query='
      mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
        updateProjectV2ItemFieldValue(input: {
          projectId: $projectId
          itemId: $itemId
          fieldId: $fieldId
          value: { singleSelectOptionId: $optionId }
        }) {
          projectV2Item { id }
        }
      }
    ' 2>/dev/null || echo "Warning: GraphQL mutation failed for issue #${issue_number}; tracker status not updated."
}
