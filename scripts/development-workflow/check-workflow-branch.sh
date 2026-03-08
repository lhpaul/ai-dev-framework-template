#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <branch-name>" >&2
  exit 2
fi

branch_name="$1"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"

cd "$repo_root"

local_match="$(git branch --list "$branch_name" | sed 's/^..//')"
remote_match="$(git branch -r --list "*/$branch_name" | sed 's/^..//')"
worktree_match="$(git worktree list | grep -F "[$branch_name]" || true)"

if [ -n "$local_match" ]; then
  echo "local: $local_match"
fi

if [ -n "$remote_match" ]; then
  printf '%s\n' "$remote_match" | while IFS= read -r line; do
    [ -n "$line" ] && echo "remote: $line"
  done
fi

if [ -n "$worktree_match" ]; then
  printf '%s\n' "$worktree_match" | while IFS= read -r line; do
    [ -n "$line" ] && echo "worktree: $line"
  done
fi

if [ -n "$local_match" ] || [ -n "$remote_match" ] || [ -n "$worktree_match" ]; then
  exit 0
fi

echo "missing: $branch_name"
exit 1
