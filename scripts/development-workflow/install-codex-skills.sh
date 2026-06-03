#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)"
REPO_SKILL_SOURCE_DIR="$REPO_ROOT/.agents/skills"
LEGACY_SOURCE_DIR="$REPO_ROOT/.codex/skills"
PRIMARY_DEST_ROOT="${AGENTS_HOME:-$HOME/.agents}/skills"
LEGACY_DEST_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"

if [ ! -d "$REPO_SKILL_SOURCE_DIR" ]; then
  echo "Skill source directory not found: $REPO_SKILL_SOURCE_DIR" >&2
  exit 1
fi

install_skill_tree() {
  local source_dir="$1"
  local dest_root="$2"
  local label="$3"

  [ -d "$source_dir" ] || return 0

  mkdir -p "$dest_root"

  for skill_dir in "$source_dir"/*; do
    [ -d "$skill_dir" ] || continue

    local skill_name
    local dest_path
    skill_name="$(basename "$skill_dir")"
    dest_path="$dest_root/$skill_name"

    if [ -e "$dest_path" ] && [ ! -L "$dest_path" ]; then
      echo "Skipping $skill_name: $dest_path exists and is not a symlink"
      continue
    fi

    ln -sfn "$skill_dir" "$dest_path"
    echo "Installed $skill_name -> $dest_path ($label)"
  done
}

install_skill_tree "$REPO_SKILL_SOURCE_DIR" "$PRIMARY_DEST_ROOT" "repo"
install_skill_tree "$LEGACY_SOURCE_DIR" "$LEGACY_DEST_ROOT" "legacy canonical"
install_skill_tree "$REPO_SKILL_SOURCE_DIR" "$LEGACY_DEST_ROOT" "legacy aliases"
