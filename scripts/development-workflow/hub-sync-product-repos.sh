#!/usr/bin/env bash
# hub-sync-product-repos.sh - safely sync workflow-hub product checkouts.

set -euo pipefail
trap 'case $? in 141) exit 0 ;; *) exit $? ;; esac' EXIT

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/hub-product-repo-lib.sh
source "$SCRIPT_DIR/hub-product-repo-lib.sh"

usage() {
  cat <<'USAGE'
Usage: hub-sync-product-repos.sh (--repo <name> | --all) [--repo-root <path>] [--bootstrap-local-path] [--yes]

Prepare workflow_hub product repository checkouts. The command refuses dirty,
ahead-only, or diverged checkouts and only fast-forwards clean repositories.
It fails before checkout inspection unless the repository is in workflow_hub
mode. Missing local paths can be written to .ai-dev-workflow.local.yaml only
with --bootstrap-local-path and explicit confirmation; --yes confirms.
USAGE
}

confirm_bootstrap() {
  local repo_name="$1"
  local local_path="$2"
  if [ "$YES" = "true" ]; then
    return 0
  fi
  printf "Write local_path '%s' for product repo '%s' to .ai-dev-workflow.local.yaml? [y/N] " "$local_path" "$repo_name" >&2
  IFS= read -r answer || return 1
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

sync_one_repo() {
  local selected_repo="$1"
  local context local_path default_branch current_branch remote_ref ahead behind counts dirty_output

  if ! context="$(hub_resolve_context_json "$REPO_ROOT" "$selected_repo")"; then
    printf 'REPO %s STATUS=failed\n' "$selected_repo"
    failed_count=$((failed_count + 1))
    return 1
  fi

  local_path="$(hub_json_field "$context" TARGET_LOCAL_PATH)"
  default_branch="$(hub_json_field "$context" TARGET_DEFAULT_BRANCH)"
  [ -n "$default_branch" ] || default_branch="main"

  printf 'REPO %s\n' "$selected_repo"
  printf '  DEFAULT_BRANCH=%s\n' "$default_branch"

  if [ -z "$local_path" ]; then
    local_path="$(hub_default_local_path "$REPO_ROOT" "$selected_repo")"
    printf '  STATUS=missing_path\n'
    printf '  SUGGESTED_LOCAL_PATH=%s\n' "$local_path"
    hub_missing_path_guidance "$selected_repo" | sed 's/^/  /'
    if [ "$BOOTSTRAP_LOCAL_PATH" = "true" ]; then
      if confirm_bootstrap "$selected_repo" "$local_path"; then
        python3 "$HUB_RESOLVER" set-local-path --repo-root "$REPO_ROOT" --repo "$selected_repo" --local-path "$local_path" >/dev/null
        printf '  BOOTSTRAP=written\n'
        skipped_count=$((skipped_count + 1))
        return 0
      fi
      printf '  BOOTSTRAP=declined\n'
    fi
    missing_count=$((missing_count + 1))
    return 1
  fi

  printf '  LOCAL_PATH=%s\n' "$local_path"
  if [ ! -d "$local_path/.git" ]; then
    printf '  STATUS=missing_checkout\n'
    printf '  GUIDANCE=create or clone the checkout at %s\n' "$local_path"
    missing_count=$((missing_count + 1))
    return 1
  fi

  if ! dirty_output="$(git -C "$local_path" status --porcelain 2>/dev/null)"; then
    printf '  STATUS=failed\n'
    printf '  REASON=working_tree_inspection_failed\n'
    failed_count=$((failed_count + 1))
    return 1
  fi

  if [ -n "$dirty_output" ]; then
    printf '  STATUS=blocked\n'
    printf '  REASON=dirty_checkout\n'
    printf '  PATH=%s\n' "$local_path"
    blocked_count=$((blocked_count + 1))
    return 1
  fi

  if ! git -C "$local_path" remote get-url origin >/dev/null 2>&1; then
    printf '  STATUS=failed\n'
    printf '  REASON=missing_origin_remote\n'
    failed_count=$((failed_count + 1))
    return 1
  fi

  if ! git -C "$local_path" fetch origin "$default_branch" >/dev/null 2>&1; then
    printf '  STATUS=failed\n'
    printf '  REASON=fetch_failed\n'
    failed_count=$((failed_count + 1))
    return 1
  fi

  if ! current_branch="$(git -C "$local_path" rev-parse --abbrev-ref HEAD 2>/dev/null)"; then
    printf '  STATUS=failed\n'
    printf '  REASON=current_branch_unreadable\n'
    failed_count=$((failed_count + 1))
    return 1
  fi
  printf '  BRANCH_BEFORE=%s\n' "$current_branch"

  if [ "$current_branch" != "$default_branch" ]; then
    if ! git -C "$local_path" checkout "$default_branch" >/dev/null 2>&1; then
      printf '  STATUS=failed\n'
      printf '  REASON=default_branch_checkout_failed\n'
      failed_count=$((failed_count + 1))
      return 1
    fi
  fi

  remote_ref="origin/$default_branch"
  if ! git -C "$local_path" rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
    printf '  STATUS=failed\n'
    printf '  REASON=remote_branch_missing\n'
    failed_count=$((failed_count + 1))
    return 1
  fi

  counts="$(git -C "$local_path" rev-list --left-right --count "HEAD...$remote_ref")"
  ahead="${counts%%[[:space:]]*}"
  behind="${counts##*[[:space:]]}"

  if [ "$ahead" -gt 0 ]; then
    printf '  STATUS=blocked\n'
    printf '  REASON=local_ahead_or_diverged\n'
    printf '  AHEAD=%s\n' "$ahead"
    printf '  BEHIND=%s\n' "$behind"
    blocked_count=$((blocked_count + 1))
    return 1
  fi

  if [ "$behind" -gt 0 ]; then
    if ! git -C "$local_path" merge --ff-only "$remote_ref" >/dev/null 2>&1; then
      printf '  STATUS=failed\n'
      printf '  REASON=fast_forward_failed\n'
      failed_count=$((failed_count + 1))
      return 1
    fi
    printf '  STATUS=synced\n'
    synced_count=$((synced_count + 1))
  else
    printf '  STATUS=skipped\n'
    printf '  REASON=already_current\n'
    skipped_count=$((skipped_count + 1))
  fi

  printf '  BRANCH_AFTER=%s\n' "$(git -C "$local_path" rev-parse --abbrev-ref HEAD)"
  return 0
}

REPO_NAME=""
ALL=false
REPO_ROOT="$HUB_REPO_ROOT"
BOOTSTRAP_LOCAL_PATH=false
YES=false

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
    --bootstrap-local-path)
      BOOTSTRAP_LOCAL_PATH=true
      shift
      ;;
    --yes)
      YES=true
      shift
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

synced_count=0
skipped_count=0
missing_count=0
blocked_count=0
failed_count=0
exit_code=0
selected_repos="$(hub_selected_repos "$REPO_ROOT" "$REPO_NAME" "$ALL")"

while IFS= read -r selected_repo; do
  [ -n "$selected_repo" ] || continue
  sync_one_repo "$selected_repo" || exit_code=1
done <<< "$selected_repos"

hub_print_summary "$synced_count" "$skipped_count" 0 0 "$missing_count" "$blocked_count" "$failed_count"
exit "$exit_code"
