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
