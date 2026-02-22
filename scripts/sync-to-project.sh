#!/usr/bin/env bash
# sync-to-project.sh
#
# Syncs framework files from ai-dev-framework-template to a target project.
# Only copies "framework-level" files — never overwrites project-specific docs.
#
# Usage:
#   ./scripts/sync-to-project.sh /path/to/your-project
#   ./scripts/sync-to-project.sh /path/to/your-project --dry-run
#
# What gets synced (framework-level):
#   docs/ai/                         → full directory
#   docs/best-practices/1-general.md
#   docs/best-practices/2-version-control.md
#   docs/best-practices/3-testing.md
#   .claude/agents/
#   .cursor/rules/
#   .cursor/commands/
#
# What does NOT get synced (project-specific):
#   docs/project/
#   docs/best-practices/STACK-SPECIFIC.md
#   AGENTS.md
#   README.md
#   CHANGELOG.md

set -euo pipefail

# ── Helpers ────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}▸ $*${RESET}"; }
success() { echo -e "${GREEN}✓ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $*${RESET}"; }
error()   { echo -e "${RED}✗ $*${RESET}" >&2; }

# ── Args ───────────────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <target-project-path> [--dry-run]"
  echo ""
  echo "  <target-project-path>   Absolute or relative path to the target project"
  echo "  --dry-run               Show what would be copied without making changes"
  exit 1
fi

TARGET="$1"
DRY_RUN=false
if [[ "${2:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

TEMPLATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Validate ───────────────────────────────────────────────────────────────────

if [[ ! -d "$TARGET" ]]; then
  error "Target directory not found: $TARGET"
  exit 1
fi

if [[ ! -f "$TARGET/AGENTS.md" ]] && [[ ! -f "$TARGET/CLAUDE.md" ]]; then
  warn "Target does not look like a project using this framework (no AGENTS.md or CLAUDE.md found)."
  read -r -p "Continue anyway? [y/N] " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# ── Files and directories to sync ─────────────────────────────────────────────

# Directories (copied recursively, destination is created if missing)
SYNC_DIRS=(
  "docs/ai"
  ".claude/agents"
  ".cursor/rules"
  ".cursor/commands"
)

# Individual files
SYNC_FILES=(
  "docs/best-practices/1-general.md"
  "docs/best-practices/2-version-control.md"
  "docs/best-practices/3-testing.md"
)

# ── Preview ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}AI Dev Framework — Sync to Project${RESET}"
echo -e "  Template : ${TEMPLATE_ROOT}"
echo -e "  Target   : ${TARGET}"
if $DRY_RUN; then
  echo -e "  Mode     : ${YELLOW}DRY RUN — no changes will be made${RESET}"
fi
echo ""

# ── Sync function ─────────────────────────────────────────────────────────────

sync_item() {
  local src="$1"
  local dest="$2"

  if $DRY_RUN; then
    if [[ -e "$dest" ]]; then
      info "[dry-run] Would update: $dest"
    else
      info "[dry-run] Would create: $dest"
    fi
    return
  fi

  local dest_dir
  dest_dir="$(dirname "$dest")"
  mkdir -p "$dest_dir"
  cp -r "$src" "$dest"
}

# ── Sync directories ──────────────────────────────────────────────────────────

echo -e "${BOLD}Directories:${RESET}"
for dir in "${SYNC_DIRS[@]}"; do
  src="${TEMPLATE_ROOT}/${dir}"
  dest="${TARGET}/${dir}"

  if [[ ! -d "$src" ]]; then
    warn "Source directory not found, skipping: $src"
    continue
  fi

  if $DRY_RUN; then
    info "[dry-run] Would sync: ${dir}/"
  else
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
    success "Synced: ${dir}/"
  fi
done

echo ""

# ── Sync individual files ─────────────────────────────────────────────────────

echo -e "${BOLD}Files:${RESET}"
for file in "${SYNC_FILES[@]}"; do
  src="${TEMPLATE_ROOT}/${file}"
  dest="${TARGET}/${file}"

  if [[ ! -f "$src" ]]; then
    warn "Source file not found, skipping: $src"
    continue
  fi

  if $DRY_RUN; then
    info "[dry-run] Would sync: ${file}"
  else
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    success "Synced: ${file}"
  fi
done

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
if $DRY_RUN; then
  warn "Dry run complete. Run without --dry-run to apply changes."
else
  success "Sync complete."
  echo ""
  echo -e "${BOLD}Next steps:${RESET}"
  echo "  1. Review the changes in ${TARGET}"
  echo "     cd \"${TARGET}\" && git diff"
  echo ""
  echo "  2. If the changes look good, commit them:"
  echo "     git add docs/ai .claude/agents .cursor docs/best-practices"
  echo "     git commit -m 'chore: sync framework from ai-dev-framework-template'"
  echo ""
  echo "  3. If a project has customized any synced files, resolve conflicts manually."
fi
echo ""
