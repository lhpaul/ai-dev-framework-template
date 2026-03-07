#!/usr/bin/env bash

set -euo pipefail

workflow_script_dir() {
  CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
}

workflow_repo_root() {
  CDPATH= cd -- "$(workflow_script_dir)/.." && pwd
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
  local remote_url
  remote_url="$(git remote get-url origin)"
  remote_url="${remote_url#git@github.com:}"
  remote_url="${remote_url#https://github.com/}"
  remote_url="${remote_url%.git}"
  printf '%s\n' "$remote_url"
}

branch_prefix() {
  case "$1" in
    spec/*) printf 'spec\n' ;;
    implementation-plan/*) printf 'implementation-plan\n' ;;
    feature/*) printf 'feature\n' ;;
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
    feature|fix|hotfix) printf 'code-reviewer\n' ;;
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

  while IFS= read -r line; do
    normalized_line="${line%$'\r'}"
    normalized_line="${normalized_line#"${normalized_line%%[![:space:]]*}"}"
    [ -z "$normalized_line" ] && continue
    saw_content=1

    while IFS= read -r prefix; do
      [ -z "$prefix" ] && continue
      case "$normalized_line" in
        "$prefix"*) continue 2 ;;
      esac
    done < <(soft_suggestion_prefixes)

    return 1
  done <<< "$body"

  [ "$saw_content" -eq 1 ]
}

open_pr_number_for_branch() {
  require_gh
  gh pr list --head "$1" --state open --json number --jq '.[0].number // empty'
}
