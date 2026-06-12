#!/usr/bin/env bash
# Shared helpers for workflow-hub product repository commands.

set -euo pipefail

HUB_SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034 # Sourcing command scripts use this default root.
HUB_REPO_ROOT="$(CDPATH='' cd -- "$HUB_SCRIPT_DIR/../.." && pwd)"
HUB_RESOLVER="$HUB_SCRIPT_DIR/workflow-config-resolver.py"

hub_die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

hub_json_field() {
  local json="$1"
  local key="$2"
  if ! printf '%s' "$json" | jq -re --arg key "$key" '.[$key] // ""' 2>/dev/null; then
    hub_die "resolver output did not include expected field '$key'"
  fi
}

hub_require_workflow_hub_mode() {
  local repo_root="$1"
  local mode_output mode
  if ! mode_output="$(python3 "$HUB_RESOLVER" mode --repo-root "$repo_root" --json 2>&1)"; then
    printf '%s\n' "$mode_output" >&2
    exit 1
  fi
  mode="$(hub_json_field "$mode_output" WORKFLOW_MODE)"
  if [ "$mode" != "workflow_hub" ]; then
    hub_die "workflow_hub mode is required; current mode is '$mode'"
  fi
}

hub_list_product_repos() {
  local repo_root="$1"
  local output
  if ! output="$(python3 "$HUB_RESOLVER" list-product-repos --repo-root "$repo_root" 2>&1)"; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  printf '%s\n' "$output"
}

hub_branch_is_checked_out() {
  local repo_path="$1"
  local branch="$2"
  git -C "$repo_path" worktree list --porcelain 2>/dev/null |
    awk -v branch_ref="refs/heads/$branch" '$1 == "branch" && $2 == branch_ref { found = 1 } END { exit(found ? 0 : 1) }'
}

hub_selected_repos() {
  local repo_root="$1"
  local repo_name="$2"
  local all="$3"
  if [ -n "$repo_name" ] && [ "$all" = "true" ]; then
    hub_die "--repo and --all cannot be used together"
  fi
  if [ "$all" = "true" ]; then
    hub_list_product_repos "$repo_root"
    return $?
  fi
  if [ -n "$repo_name" ]; then
    printf '%s\n' "$repo_name"
    return 0
  fi
  hub_die "select one product repository with --repo <name> or all repositories with --all"
}

hub_resolve_context_json() {
  local repo_root="$1"
  local repo_name="$2"
  local output
  if ! output="$(python3 "$HUB_RESOLVER" resolve --repo-root "$repo_root" --repo "$repo_name" --json 2>&1)"; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  printf '%s\n' "$output"
}

hub_github_repo_from_url() {
  local value="$1"
  case "$value" in
    git@github.com:*/*.git)
      value="${value#git@github.com:}"
      value="${value%.git}"
      ;;
    git@github.com:*/*)
      value="${value#git@github.com:}"
      ;;
    https://github.com/*/*.git)
      value="${value#https://github.com/}"
      value="${value%.git}"
      ;;
    https://github.com/*/*)
      value="${value#https://github.com/}"
      value="${value%/}"
      ;;
    ssh://git@github.com/*/*.git)
      value="${value#ssh://git@github.com/}"
      value="${value%.git}"
      ;;
    ssh://git@github.com/*/*)
      value="${value#ssh://git@github.com/}"
      value="${value%/}"
      ;;
    *)
      value=""
      ;;
  esac
  case "$value" in
    */*/*|/*|*/|'')
      value=""
      ;;
  esac
  printf '%s\n' "$value"
}

hub_missing_path_guidance() {
  local repo_name="$1"
  cat <<GUIDANCE
Add this local-only entry to .ai-dev-workflow.local.yaml:
product_repos:
  - name: $repo_name
    local_path: ../$repo_name
GUIDANCE
}

hub_default_local_path() {
  local repo_root="$1"
  local repo_name="$2"
  local parent
  parent="$(CDPATH='' cd -- "$repo_root/.." && pwd -P)"
  printf '%s/%s\n' "$parent" "$repo_name"
}

hub_print_summary() {
  local synced="$1"
  local skipped="$2"
  local clean="$3"
  local dirty="$4"
  local missing="$5"
  local blocked="$6"
  local failed="$7"

  printf 'SUMMARY synced=%s skipped=%s clean=%s dirty=%s missing=%s blocked=%s failed=%s\n' \
    "$synced" "$skipped" "$clean" "$dirty" "$missing" "$blocked" "$failed"
}
