#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/development-workflow/discover-workflow-state.sh [--repo <name>] [--repo-root <path>]

Discovers workflow state. In workflow_hub mode, --repo selects the product
repository used for implementation branch and PR inspection.
EOF
}

target_repo=""
repo_root="$REPO_ROOT"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      target_repo="${2:?--repo requires a value}"
      shift 2
      ;;
    --repo-root)
      repo_root="${2:?--repo-root requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
  esac
done

cd "$repo_root"

mode_context="$(workflow_repository_mode "$repo_root")"
workflow_mode="$(workflow_context_value WORKFLOW_MODE "$mode_context")"
repo_context=""
target_github_repo=""
target_local_path=""
target_repo_name=""
target_default_branch=""

if [ "$workflow_mode" = "workflow_hub" ]; then
  if repo_context="$(workflow_repository_context "$target_repo" "$repo_root" 2>/dev/null)"; then
    target_github_repo="$(workflow_github_repo_from_context "$repo_context")"
    target_local_path="$(workflow_context_value TARGET_LOCAL_PATH "$repo_context")"
    target_repo_name="$(workflow_context_value TARGET_REPO_NAME "$repo_context")"
    target_default_branch="$(workflow_context_value TARGET_DEFAULT_BRANCH "$repo_context")"
  fi
else
  repo_context="$(workflow_repository_context "" "$repo_root")"
  target_github_repo="$(workflow_github_repo_from_context "$repo_context")"
  target_local_path="$(workflow_context_value TARGET_LOCAL_PATH "$repo_context")"
  target_repo_name="$(workflow_context_value TARGET_REPO_NAME "$repo_context")"
  target_default_branch="$(workflow_context_value TARGET_DEFAULT_BRANCH "$repo_context")"
fi

echo "== repository context =="
print_kv WORKFLOW_MODE "$workflow_mode"
if [ "$workflow_mode" = "workflow_hub" ]; then
  if [ -n "$repo_context" ]; then
    print_kv ACTION_REPOSITORY_KIND "product_repo_owned"
    print_kv ACTION_REPOSITORY "$target_repo_name"
    print_kv TARGET_GITHUB_REPO "$target_github_repo"
    print_kv TARGET_LOCAL_PATH "$target_local_path"
    print_kv TARGET_DEFAULT_BRANCH "$target_default_branch"
  else
    print_kv ACTION_REPOSITORY_KIND "selection_missing"
    print_kv ACTION_REPOSITORY ""
    echo "NOTE: product repository selection is required for product-owned implementation branch and PR inspection."
  fi
else
  print_kv ACTION_REPOSITORY_KIND "single_repo_context"
  print_kv ACTION_REPOSITORY "$target_repo_name"
  print_kv TARGET_GITHUB_REPO "$target_github_repo"
fi
echo

# Check if an issue tracker is configured and remind the caller
tracker_provider="$(workflow_config_provider issue_tracker)"
if [ -n "$tracker_provider" ] && [ "$tracker_provider" != "none" ]; then
  echo "== issue tracker =="
  echo "Provider: $tracker_provider (query the tracker for authoritative item status)"
  echo "NOTE: Development folders and VCS state below are supplementary — the tracker is the primary source of truth."
  echo
fi

echo "== git status =="
git status --short --branch

echo
echo "== workflow branches =="
branch_refs="$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes)"
if [ -n "$branch_refs" ]; then
  printf '%s\n' "$branch_refs" | grep -E '(^|/)(spec|implementation-plan|feature|refactor|fix|hotfix|release)/' || true
fi
if [ "$workflow_mode" = "workflow_hub" ] && [ -n "$target_local_path" ] && [ -d "$target_local_path/.git" ]; then
  echo
  echo "== product workflow branches =="
  product_branch_refs="$(git -C "$target_local_path" for-each-ref --format='%(refname:short)' refs/heads refs/remotes)"
  if [ -n "$product_branch_refs" ]; then
    printf '%s\n' "$product_branch_refs" | grep -E '(^|/)(feature|refactor|fix|hotfix)/' || true
  fi
fi

echo
echo "== worktrees =="
git worktree list
if [ "$workflow_mode" = "workflow_hub" ] && [ -n "$target_local_path" ] && [ -d "$target_local_path/.git" ]; then
  echo
  echo "== product worktrees =="
  git -C "$target_local_path" worktree list
fi

echo
echo "== development folders =="
if [ -d "docs/specs/developments" ]; then
  find "docs/specs/developments" -mindepth 1 -maxdepth 1 -type d | sort
else
  echo "(none)"
fi

echo
echo "== open pull requests =="
if gh_available; then
  echo "-- hub repository --"
  gh pr list --state open --json number,title,headRefName,baseRefName,labels,statusCheckRollup \
    --jq '
      if length == 0 then
        "(none)"
      else
        .[]
        | [
            ("#" + (.number | tostring)),
            .headRefName,
            ("base=" + .baseRefName),
            ("labels=" + ([.labels[].name] | join(","))),
            ("checks=" + (
              [.statusCheckRollup[]? | (.conclusion // .state // .status // "unknown")]
              | join(",")
            )),
            .title
          ]
        | @tsv
      end
    '
  if [ "$workflow_mode" = "workflow_hub" ] && [ -n "$target_github_repo" ]; then
    echo "-- product repository: $target_github_repo --"
    gh pr list --repo "$target_github_repo" --state open --json number,title,headRefName,baseRefName,labels,statusCheckRollup \
      --jq '
        if length == 0 then
          "(none)"
        else
          .[]
          | [
              ("#" + (.number | tostring)),
              .headRefName,
              ("base=" + .baseRefName),
              ("labels=" + ([.labels[].name] | join(","))),
              ("checks=" + (
                [.statusCheckRollup[]? | (.conclusion // .state // .status // "unknown")]
                | join(",")
              )),
              .title
            ]
          | @tsv
        end
      '
  fi
else
  echo "(gh unavailable)"
fi
