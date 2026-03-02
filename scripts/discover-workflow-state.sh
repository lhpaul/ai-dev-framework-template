#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

echo "== git status =="
git status --short --branch

echo
echo "== workflow branches =="
branch_refs="$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes)"
if [ -n "$branch_refs" ]; then
  printf '%s\n' "$branch_refs" | grep -E '(^|/)(spec|implementation-plan|feature|fix|hotfix|release)/' || true
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
