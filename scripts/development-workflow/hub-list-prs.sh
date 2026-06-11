#!/usr/bin/env bash
# hub-list-prs.sh - list product repository pull requests from a workflow hub.

set -euo pipefail
trap 'case $? in 141) exit 0 ;; *) exit $? ;; esac' EXIT

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/hub-product-repo-lib.sh
source "$SCRIPT_DIR/hub-product-repo-lib.sh"

usage() {
  cat <<'USAGE'
Usage: hub-list-prs.sh (--repo <name> | --all) [--repo-root <path>]

List open pull requests for workflow_hub product repositories. The command is
read-only, requires workflow_hub mode, resolves each product repository's
GitHub owner/repo identity, and never falls back to the hub repository.
USAGE
}

REPO_NAME=""
ALL=false
REPO_ROOT="$HUB_REPO_ROOT"
PR_LIST_LIMIT=1000

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || hub_die "--repo requires a value"
      REPO_NAME="$2"
      shift 2
      ;;
    --all)
      ALL=true
      shift
      ;;
    --repo-root)
      [ "$#" -ge 2 ] || hub_die "--repo-root requires a value"
      REPO_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      hub_die "unknown argument '$1'"
      ;;
  esac
done

hub_require_workflow_hub_mode "$REPO_ROOT"

failed_count=0
clean_count=0
exit_code=0
selected_repos="$(hub_selected_repos "$REPO_ROOT" "$REPO_NAME" "$ALL")"

while IFS= read -r selected_repo; do
  [ -n "$selected_repo" ] || continue
  if ! context="$(hub_resolve_context_json "$REPO_ROOT" "$selected_repo")"; then
    printf 'REPO %s STATUS=failed\n' "$selected_repo"
    failed_count=$((failed_count + 1))
    exit_code=1
    continue
  fi

  github_repo="$(hub_json_field "$context" TARGET_GITHUB_REPO)"
  git_url="$(hub_json_field "$context" TARGET_GIT_URL)"
  if [ -z "$github_repo" ] && [ -n "$git_url" ]; then
    github_repo="$(hub_github_repo_from_url "$git_url")"
  fi

  printf 'REPO %s\n' "$selected_repo"
  if [ -z "$github_repo" ]; then
    printf '  STATUS=failed\n'
    printf '  REASON=no_github_repo_slug\n'
    printf '  GUIDANCE=configure github_repo or a GitHub-form git_url for this product repository\n'
    failed_count=$((failed_count + 1))
    exit_code=1
    continue
  fi

  printf '  GITHUB_REPO=%s\n' "$github_repo"
  if ! pr_output="$(gh pr list --repo "$github_repo" --state open --limit "$PR_LIST_LIMIT" --json number,title,headRefName,baseRefName,isDraft,labels 2>&1)"; then
    printf '  STATUS=failed\n'
    printf '  REASON=remote_inspection_failed\n'
    printf '%s\n' "$pr_output" | sed 's/^/  gh: /'
    failed_count=$((failed_count + 1))
    exit_code=1
    continue
  fi

  if ! formatted_prs="$(printf '%s' "$pr_output" | jq -r '
    if length == 0 then
      "  PRS=none"
    else
      .[] |
      "  PR #\(.number) title=\(.title) head=\(.headRefName) base=\(.baseRefName) draft=\(.isDraft) labels=\([.labels[].name] | join(","))"
    end
  ' 2>/dev/null)"; then
    printf '  STATUS=failed\n'
    printf '  REASON=pr_json_parse_failed\n'
    failed_count=$((failed_count + 1))
    exit_code=1
    continue
  fi

  printf '  STATUS=clean\n'
  clean_count=$((clean_count + 1))
  printf '%s\n' "$formatted_prs"
done <<< "$selected_repos"

hub_print_summary 0 0 "$clean_count" 0 0 0 "$failed_count"
exit "$exit_code"
