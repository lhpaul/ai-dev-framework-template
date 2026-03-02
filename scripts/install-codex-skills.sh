#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/.codex/skills"
DEST_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "Skill source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$DEST_ROOT"

for skill_dir in "$SOURCE_DIR"/*; do
  [ -d "$skill_dir" ] || continue

  skill_name="$(basename "$skill_dir")"
  dest_path="$DEST_ROOT/$skill_name"

  if [ -e "$dest_path" ] && [ ! -L "$dest_path" ]; then
    echo "Skipping $skill_name: $dest_path exists and is not a symlink"
    continue
  fi

  ln -sfn "$skill_dir" "$dest_path"
  echo "Installed $skill_name -> $dest_path"
done
