#!/usr/bin/env bash
# hub-status.sh - inspect workflow-hub product repository checkouts.

set -euo pipefail
trap 'case $? in 141) exit 0 ;; *) exit $? ;; esac' EXIT

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/hub-product-repo-lib.sh
source "$SCRIPT_DIR/hub-product-repo-lib.sh"

usage() {
  cat <<'USAGE'
Usage: hub-status.sh (--repo <name> | --all) [--repo-root <path>]

Inspect workflow_hub product repository checkouts without modifying them.
Reports local path, branch, clean/dirty state, remote visibility, and a final
summary. Fails before checkout inspection unless the repository is in
workflow_hub mode. Missing local paths include .ai-dev-workflow.local.yaml
guidance.
USAGE
}

REPO_NAME=""
ALL=false
REPO_ROOT="$HUB_REPO_ROOT"

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

clean_count=0
dirty_count=0
missing_count=0
failed_count=0
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

  local_path="$(hub_json_field "$context" TARGET_LOCAL_PATH)"
  local_source="$(hub_json_field "$context" TARGET_LOCAL_PATH_SOURCE)"
  printf 'REPO %s\n' "$selected_repo"
  printf '  LOCAL_PATH=%s\n' "${local_path:-}"
  printf '  LOCAL_PATH_SOURCE=%s\n' "${local_source:-}"

  if [ -z "$local_path" ]; then
    printf '  STATUS=missing_path\n'
    hub_missing_path_guidance "$selected_repo" | sed 's/^/  /'
    missing_count=$((missing_count + 1))
    exit_code=1
    continue
  fi

  if [ ! -d "$local_path/.git" ]; then
    printf '  STATUS=missing_checkout\n'
    printf '  GUIDANCE=create or clone the checkout at %s\n' "$local_path"
    missing_count=$((missing_count + 1))
    exit_code=1
    continue
  fi

  if ! branch="$(git -C "$local_path" rev-parse --abbrev-ref HEAD 2>/dev/null)"; then
    printf '  STATUS=failed\n'
    printf '  ERROR=could not read current branch\n'
    failed_count=$((failed_count + 1))
    exit_code=1
    continue
  fi
  printf '  BRANCH=%s\n' "$branch"

  if [ -n "$(git -C "$local_path" status --porcelain)" ]; then
    printf '  STATUS=dirty\n'
    dirty_count=$((dirty_count + 1))
  else
    printf '  STATUS=clean\n'
    clean_count=$((clean_count + 1))
  fi

  if remote_url="$(git -C "$local_path" remote get-url origin 2>/dev/null)"; then
    printf '  REMOTE=available\n'
    printf '  REMOTE_URL=%s\n' "$remote_url"
  else
    printf '  REMOTE=unavailable\n'
  fi
done <<< "$selected_repos"

hub_print_summary 0 0 "$clean_count" "$dirty_count" "$missing_count" 0 "$failed_count"
exit "$exit_code"
