#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

cd "$REPO_ROOT"

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

echo
echo "== worktrees =="
git worktree list

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
else
  echo "(gh unavailable)"
fi
